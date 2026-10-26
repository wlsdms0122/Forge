//
//  ScheduleCreateMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ScheduleCreateMethod: Sendable {
    // MARK: - Property
    let store: ScheduleStore
    let catalog: WorkflowCatalog
    let policyStore: PolicyStore

    // MARK: - Initializer
    init(
        store: ScheduleStore,
        catalog: WorkflowCatalog,
        policyStore: PolicyStore
    ) {
        self.store = store
        self.catalog = catalog
        self.policyStore = policyStore
    }

    // MARK: - Public
    // The trigger the request gives, read by `Trigger`'s rules; `after` is a
    // fire time relative to now, and a `once` must lie ahead of now.
    static func parseTrigger(_ params: [String: JSONValue], now: Date = Date()) throws -> Trigger {
        let fields = Trigger.CodingKeys.allCases.reduce(into: [String: JSONValue]()) { fields, key in
            guard let value = params[key.stringValue], value.stringValue != "" else { return }
            
            fields[key.stringValue] = value
        }
        
        if let after = params["after"]?.stringValue.flatMap({ value in value.isEmpty ? nil : value }) {
            guard fields.isEmpty else {
                throw ProtocolError(
                    "schedule.create: 'after' is a fire time relative to now and takes no"
                        + " 'once', 'every', 'at', 'days' or 'timezone'"
                )
            }
            
            let seconds: Int
            
            do {
                seconds = try Interval.parse(after)
            } catch {
                throw ProtocolError(
                    "schedule.create: 'after' must be a duration like 30s / 5m / 1h / 2d (compound 1h30m): '\(after)'")
            }
            
            return .once(
                fireAt: now.addingTimeInterval(Double(seconds)),
                timezone: TimeZone(identifier: "UTC")!
            )
        }
        
        let trigger: Trigger
        
        do {
            trigger = try JSONDecoder().decode(
                Trigger.self,
                from: try JSONEncoder().encode(JSONValue.object(fields))
            )
        } catch {
            throw ProtocolError("schedule.create: \(friendlyDecodingError(error, root: "trigger"))")
        }
        
        if case let .once(fireAt, timezone) = trigger, fireAt <= now {
            throw ProtocolError(
                "schedule.create: fire time must be in the future (\(Trigger.formatWallClock(fireAt, timezone: timezone)) \(timezone.identifier))")
        }
        
        return trigger
    }

    static func fireAt(_ trigger: Trigger) -> Date? {
        if case .once(let date, _) = trigger { return date }

        return nil
    }

    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONValue {
        let (workflowName, specJSON) = try await Self.resolveDispatchTarget(
            params: request.params,
            context: "schedule.create",
            catalog: catalog
        )

        try await DispatchAuthorization.requireDispatch(
            claims: claims,
            workflow: workflowName,
            policyStore: policyStore,
            context: "schedule.create"
        )

        let trigger = try Self.parseTrigger(request.params, now: Date())
        let concurrency: ConcurrencyPolicy

        if let raw = request.params["concurrency"]?.stringValue {
            guard let policy = ConcurrencyPolicy(rawValue: raw) else {
                throw ProtocolError("schedule.create: concurrency must be one of queue|skip|replace — '\(raw)'")
            }

            concurrency = policy
        } else {
            concurrency = .queue
        }

        let inputs = request.params["inputs"]?.objectValue

        let scheduleID: String

        if let given = request.params["id"]?.stringValue, !given.isEmpty {
            scheduleID = given
        } else {
            scheduleID = "s-\(Int(Date().timeIntervalSince1970))-"
                + UUID().uuidString.prefix(6).lowercased()
        }

        let requested = Schedule(
            id: scheduleID,
            workflow: workflowName,
            trigger: trigger,
            concurrency: concurrency,
            enabled: true,
            inputs: inputs,
            spec: specJSON
        )
        let created = try await store.create(requested)

        var out: [String: JSONValue] = [
            "id":       .string(created.id),
            "workflow": .string(workflowName),
            "trigger":  try JSONValue(encoding: trigger),
            "runtime":  true
        ]

        if let at = Self.fireAt(trigger) {
            out["fire_at"] = .string(ISO8601.string(at))
        }

        return .object(out)
    }

    // MARK: - Private
    private static func friendlyDecodingError(_ error: Error, root: String) -> String {
        guard let decodingError = error as? DecodingError else { return "\(error)" }

        func location(_ context: DecodingError.Context) -> String {
            var path = root

            for key in context.codingPath {
                if let index = key.intValue {
                    path += "[\(index)]"
                } else {
                    path += ".\(key.stringValue)"
                }
            }

            return path
        }

        func jsonType(_ type: Any.Type) -> String {
            let name = String(describing: type)

            if name.contains("Dictionary") { return "object" }
            if name.contains("Array")  { return "array" }
            if name.contains("String") { return "string" }
            if name.contains("Bool")   { return "boolean" }
            if name.contains("Int") || name.contains("Double") || name.contains("Float") {
                return "number"
            }

            return name
        }

        switch decodingError {
        case .keyNotFound(let key, let context):
            return "\(location(context)): missing required key '\(key.stringValue)'"

        case .typeMismatch(let type, let context):
            return "\(location(context)): expected \(jsonType(type))"

        case .valueNotFound(let type, let context):
            return "\(location(context)): value missing (expected \(jsonType(type)))"

        case .dataCorrupted(let context):
            let at = context.codingPath.isEmpty ? root : location(context)
            var message = context.debugDescription

            if let underlying = context.underlyingError {
                let detail = "\(underlying)".trimmingCharacters(in: .whitespacesAndNewlines)

                if !detail.isEmpty { message += " — \(detail)" }
            }

            return "\(at): \(message)"

        @unknown default:
            return "\(error)"
        }
    }

    private static func resolveDispatchTarget(
        params: [String: JSONValue],
        context: String,
        catalog: WorkflowCatalog
    ) async throws -> (name: String, spec: JSONValue?) {
        let nameParam = params["workflow"]?.stringValue
            .flatMap { value in value.isEmpty ? nil : value }
        let specParam = params["spec"]?.objectValue

        switch (nameParam, specParam) {
        case let (name?, nil):
            _ = try await catalog.workflow(named: name)

            return (name, nil)

        case let (nil, raw?):
            guard raw["name"] == nil else {
                throw ProtocolError(
                    "\(context): inline 'spec' must be anonymous — a 'name' key is not allowed (the name is fixed to '\(WorkflowCatalog.inlineSigil)')")
            }

            let specValue = JSONValue.object(raw)

            do {
                // An inline spec is one procedure, the same shape workflow.dispatch
                // admits — checked here so a schedule cannot be stored carrying
                // something that will not load when it fires.
                _ = try await catalog.inline(specValue)
            } catch {
                throw ProtocolError("\(context): malformed 'spec' — \(ErrorObject(error).message)")
            }

            return (WorkflowCatalog.inlineSigil, specValue)

        case (.some, .some):
            throw ProtocolError(
                "\(context): 'workflow' and 'spec' are mutually exclusive — pass only one")

        case (nil, nil):
            throw ProtocolError(
                "\(context): one of 'workflow' (registered name) or 'spec' (inline workflow JSON) is required")
        }
    }
}
