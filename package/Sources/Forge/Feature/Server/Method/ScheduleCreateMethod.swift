//
//  ScheduleCreateMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

struct ScheduleCreateMethod: Sendable {
    // MARK: - Property
    let store: ScheduleStore
    let workflowStore: SpecCatalog
    let policyStore: PolicyStore
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(
        store: ScheduleStore,
        workflowStore: SpecCatalog,
        policyStore: PolicyStore,
        tokenAuthority: TokenAuthority
    ) {
        self.store = store
        self.workflowStore = workflowStore
        self.policyStore = policyStore
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    static func parseTrigger(_ params: [String: Any], now: Date = Date()) throws -> Trigger {
        let everyRaw = (params["every"] as? String)
            .flatMap { value in value.isEmpty ? nil : value }
        let atRaw    = (params["at"]    as? String)
            .flatMap { value in value.isEmpty ? nil : value }
        let onceRaw  = (params["once"]  as? String)
            .flatMap { value in value.isEmpty ? nil : value }
        let afterRaw = (params["after"] as? String)
            .flatMap { value in value.isEmpty ? nil : value }
        let present = [everyRaw, atRaw, onceRaw, afterRaw].compactMap { value in value }

        guard present.count == 1 else {
            throw ProtocolError(
                "schedule.create: exactly one of 'every' (interval) / 'at' (wall-clock 'HH:mm' + 'timezone') / 'once' (wall-clock 'yyyy-MM-dd HH:mm:ss' + 'timezone') / 'after' (relative duration) is required")
        }

        let hasTimezone = (params["timezone"] as? String).map { value in !value.isEmpty } ?? false
        let hasDays = params["days"] != nil

        if let every = everyRaw {
            if hasTimezone || hasDays {
                throw ProtocolError("schedule.create: 'every' is timezone-agnostic and takes no 'days' — drop 'timezone'/'days'")
            }

            let seconds: Int

            do {
                seconds = try Interval.parse(every)
            } catch {
                throw ProtocolError(
                    "schedule.create: 'every' must be a duration like 30s / 5m / 1h / 2d (compound 1h30m): '\(every)'")
            }

            return .every(Interval(seconds: seconds))
        }

        if let at = atRaw {
            guard let (hour, minute) = Trigger.parseHHmm(at) else {
                throw ProtocolError("schedule.create: 'at' must be 'HH:mm' (24h): '\(at)'")
            }

            let timezone = try parseTimezone(params, context: "schedule.create")
            let days = try parseDays(params)

            return .at(hour: hour, minute: minute, days: days, timezone: timezone)
        }

        if let once = onceRaw {
            if hasDays {
                throw ProtocolError("schedule.create: 'once' takes no 'days' (one-shot) — drop 'days'")
            }

            let timezone = try parseTimezone(params, context: "schedule.create")

            guard let fireAt = Trigger.parseWallClock(once, timezone: timezone) else {
                throw ProtocolError(
                    "schedule.create: 'once' must be 'yyyy-MM-dd HH:mm:ss': '\(once)'")
            }

            guard fireAt > now else {
                throw ProtocolError(
                    "schedule.create: fire time must be in the future (\(Trigger.formatWallClock(fireAt, timezone: timezone)) \(timezone.identifier))")
            }

            return .once(fireAt: fireAt, timezone: timezone)
        }

        let after = afterRaw!

        if hasTimezone || hasDays {
            throw ProtocolError("schedule.create: 'after' is timezone-agnostic and takes no 'days' — drop 'timezone'/'days'")
        }

        let seconds: Int

        do {
            seconds = try Interval.parse(after)
        } catch {
            throw ProtocolError(
                "schedule.create: 'after' must be a duration like 30s / 5m / 1h / 2d (compound 1h30m): '\(after)'")
        }

        let fireAt = now.addingTimeInterval(Double(seconds))

        return .once(fireAt: fireAt, timezone: TimeZone(identifier: "UTC")!)
    }

    static func fireAt(_ trigger: Trigger) -> Date? {
        if case .once(let date, _) = trigger { return date }

        return nil
    }

    static func parseTimezone(_ params: [String: Any], context: String) throws -> TimeZone {
        guard let identifier = params["timezone"] as? String, !identifier.isEmpty else {
            throw ProtocolError("\(context): 'timezone' (e.g. 'Asia/Seoul') is required for wall-clock trigger")
        }

        guard let timezone = TimeZone(identifier: identifier) else {
            throw ProtocolError("\(context): unknown timezone identifier '\(identifier)'")
        }

        return timezone
    }

    static func parseDays(_ params: [String: Any]) throws -> Set<Weekday> {
        guard let raw = params["days"] else { return [] }
        guard let list = raw as? [String], !list.isEmpty else {
            throw ProtocolError("schedule.create: 'days' must be a non-empty array of mon..sun (omit for every day)")
        }

        var out: Set<Weekday> = []

        for value in list {
            guard let weekday = Weekday(rawValue: value.lowercased()) else {
                throw ProtocolError("schedule.create: unknown weekday '\(value)' — use mon/tue/wed/thu/fri/sat/sun")
            }

            out.insert(weekday)
        }

        return out
    }

    func handle(_ request: RPCRequest) async throws -> JSONObject {
        let claims = try tokenAuthority.requireClaims(request.params)
        let (workflowName, specJSON) = try await resolveDispatchTarget(
            params: request.params,
            context: "schedule.create",
            workflowStore: workflowStore
        )

        try await DispatchAuthz.requireDispatch(
            claims: claims,
            workflow: workflowName,
            policyStore: policyStore,
            context: "schedule.create"
        )

        let trigger = try Self.parseTrigger(request.params, now: Date())
        let concurrency: ConcurrencyPolicy

        if let raw = request.params["concurrency"] as? String {
            guard let policy = ConcurrencyPolicy(rawValue: raw) else {
                throw ProtocolError("schedule.create: concurrency must be one of queue|skip|replace — '\(raw)'")
            }

            concurrency = policy
        } else {
            concurrency = .queue
        }

        let inputs: [String: JSONValue]?

        if let object = request.params["inputs"] as? [String: Any] {
            inputs = try decodeJSONValueDict(object)
        } else {
            inputs = nil
        }

        let scheduleID: String

        if let given = request.params["id"] as? String, !given.isEmpty {
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

        var out: [String: Any] = [
            "id":         created.id,
            "workflow":   workflowName,
            "trigger": triggerToAny(trigger),
            "runtime":  true,
        ]

        if let at = Self.fireAt(trigger) {
            out["fire_at"] = ISO8601.string(at)
        }

        return JSONObject(out)
    }

    // MARK: - Private
}

func resolveDispatchTarget(
    params: [String: Any],
    context: String,
    workflowStore: SpecCatalog
) async throws -> (name: String, spec: JSONValue?) {
    let nameParam = (params["workflow"] as? String)
        .flatMap { value in value.isEmpty ? nil : value }
    let specParam = params["spec"] as? [String: Any]

    switch (nameParam, specParam) {
    case let (name?, nil):
        switch await workflowStore.resolve(name) {
        case .found:
            return (name, nil)

        case .invalid(let reason):
            throw WorkflowValidationError("\(context): workflow '\(name)' is broken — \(reason)")

        case .unobserved(let reason):
            throw ResolutionError("\(context): workflow '\(name)' could not be resolved — \(reason)")

        case .missing:
            throw ResolutionError("\(context): workflow '\(name)' is not registered")
        }

    case let (nil, raw?):
        guard raw["name"] == nil else {
            throw ProtocolError(
                "\(context): inline 'spec' must be anonymous — a 'name' key is not allowed (the name is fixed to '\(WorkflowDispatchMethod.inlineSigil)')")
        }

        let specValue: JSONValue

        do {
            specValue = .object(try decodeJSONValueDict(raw))
        } catch {
            throw ProtocolError("\(context): failed to normalize 'spec': \(error)")
        }

        do {
            _ = try workflowStore.loader.lower(ValueBridge.value(specValue))
        } catch {
            throw ProtocolError("\(context): malformed 'spec' — \(error)")
        }

        return (WorkflowDispatchMethod.inlineSigil, specValue)

    case (.some, .some):
        throw ProtocolError(
            "\(context): 'workflow' and 'spec' are mutually exclusive — pass only one")

    case (nil, nil):
        throw ProtocolError(
            "\(context): one of 'workflow' (registered name) or 'spec' (inline workflow JSON) is required")
    }
}
