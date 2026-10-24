//
//  WorkflowDispatchMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct WorkflowDispatchMethod: Sendable {
    struct Prepared: Sendable {
        // MARK: - Property
        let workflow: Workflow
        let inputs: [String: JSONValue]
        let principal: String
        let workflowID: String
        let origin: DispatchOrigin
        let rootID: String?
        let parentNodeID: String?
        let parentRunID: String?
        let parameters: [String: JSONValue]?
        let correlator: String?

        var effectiveRootID: String { rootID ?? workflowID }

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let runner: WorkflowRunner
    let store: WorkflowCatalog
    let workRegistry: WorkRegistry

    // MARK: - Initializer
    init(
        runner: WorkflowRunner,
        store: WorkflowCatalog,
        workRegistry: WorkRegistry
    ) {
        self.runner = runner
        self.store = store
        self.workRegistry = workRegistry
    }

    // MARK: - Public
    func prepare(_ request: RPCRequest, claims: TokenClaims) async throws -> Prepared {
        let principal = claims.principal
        let record = try await workRegistry.requireLiveRecord(
            workflowID: claims.workflowID,
            context: "workflow.dispatch"
        )
        let workflow = try await resolveProgram(request.rawParams)
        let inputs = try decodeJSONValueDict(
            (request.rawParams["inputs"] as? [String: Any]) ?? [:]
        )
        let workflowID = WorkflowRunner.newRunID()
        let rootID: String?
        let parentNodeID: String?
        let parentRunID: String?
        let correlator: String?
        let parameters: [String: JSONValue]?
        let origin: DispatchOrigin

        if let record {
            rootID      = record.rootID
            parentNodeID = record.nodeID
            parentRunID  = record.workflowID
            correlator   = record.correlator
            parameters   = record.parameters
            origin      = DispatchOrigin(kind: "workflow", id: record.workflowID)
        } else {
            let rootField = request.rawParams["root"] as? [String: Any]
            rootID      = rootField?["root_id"] as? String
            parentNodeID = rootField?["parent_id"] as? String
            parentRunID  = nil
            correlator   = request.rawParams["correlator"] as? String

            if let parametersObject = request.rawParams["parameters"] as? [String: Any] {
                parameters = try decodeJSONValueDict(parametersObject)
            } else {
                parameters = nil
            }

            if let originField = request.rawParams["origin"] as? [String: Any],
                let kind = originField["kind"] as? String {
                origin = DispatchOrigin(kind: kind, id: originField["id"] as? String)
            } else {
                origin = .rpc
            }
        }

        return Prepared(
            workflow: workflow,
            inputs: inputs,
            principal: principal,
            workflowID: workflowID,
            origin: origin,
            rootID: rootID,
            parentNodeID: parentNodeID,
            parentRunID: parentRunID,
            parameters: parameters,
            correlator: correlator
        )
    }

    func runDispatch(
        _ prepared: Prepared,
        mode: DispatchMode
    ) async throws -> WorkflowRunResult {
        try await runner.dispatch(
            prepared.workflow,
            inputs: prepared.inputs,
            principal: prepared.principal,
            origin: prepared.origin,
            rootID: prepared.rootID,
            parentNodeID: prepared.parentNodeID,
            parentRunID: prepared.parentRunID,
            parameters: prepared.parameters,
            correlator: prepared.correlator,
            workflowID: prepared.workflowID,
            mode: mode
        )
    }

    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONObject {
        let prepared = try await prepare(request, claims: claims)
        let isAsync = (request.rawParams["async"] as? Bool) ?? false
        let principal = prepared.principal
        let workflowID = prepared.workflowID

        if !isAsync {
            return encodeResult(try await runDispatch(prepared, mode: .awaited))
        } else {
            try await DispatchAuthz.requireDispatch(
                principal: principal,
                workflow: prepared.workflow.name,
                policyStore: runner.policyStore,
                context: "dispatch"
            )

            let workflowName = prepared.workflow.name
            let selfLocal = self

            Task.detached {
                do {
                    _ = try await selfLocal.runDispatch(prepared, mode: .unawaited)
                } catch {
                    await Log.shared.append(
                        "dispatch.failed",
                        LogPayload([
                            "workflow":    workflowName,
                            "workflow_id": workflowID,
                            "principal":   principal,
                            "error":       String(describing: error),
                        ]),
                        level: .error,
                        category: "workflow"
                    )
                }
            }

            return [
                "workflow_id": workflowID,
                "name":        workflowName,
                "status":      "running",
            ]
        }
    }

    func encodeResult(_ result: WorkflowRunResult) -> JSONObject {
        if let failure = result.error {
            return [
                "workflow_id": result.workflowID,
                "name":        result.workflowName,
                "status":      "failed",
                "duration_ms": result.durationMs,
                "outputs":     jsonValueDictToAny(result.outputs),
                "error":       failure.object.jsonValue.jsonObject,
            ]
        }

        return [
            "workflow_id": result.workflowID,
            "name":        result.workflowName,
            "status":      "ok",
            "duration_ms": result.durationMs,
            "outputs":     jsonValueDictToAny(result.outputs),
        ]
    }

    // MARK: - Private
    private func resolveProgram(
        _ params: [String: Any]
    ) async throws -> Workflow {
        if let specObject = params["spec"] as? [String: Any] {
            guard specObject["name"] == nil else {
                throw ProtocolError("workflow.dispatch: inline 'spec' must be anonymous — a 'name' key is not allowed (the name is fixed to '\(WorkflowCatalog.inlineSigil)')")
            }

            do {
                return try await store.inline(.object(try decodeJSONValueDict(specObject)))
            } catch {
                throw ProtocolError("workflow.dispatch: malformed 'spec' — \(error)")
            }
        }

        if let name = params["name"] as? String, !name.isEmpty {
            return try await store.workflow(named: name)
        }

        throw ProtocolError("workflow.dispatch: one of 'spec' or 'name' is required")
    }
}

func decodeJSONValueDict(_ object: [String: Any]) throws -> [String: JSONValue] {
    let data = try JSONSerialization.data(withJSONObject: object)

    return try JSONDecoder().decode([String: JSONValue].self, from: data)
}

func jsonValueToAny(_ value: JSONValue) -> Any {
    switch value {
    case .null:
        return NSNull()

    case .bool(let bool):
        return bool

    case .int(let integer):
        return integer

    case .double(let double):
        return double

    case .string(let string):
        return string

    case .array(let array):
        return array.map(jsonValueToAny)

    case .object(let object):
        return object.mapValues(jsonValueToAny)
    }
}

func jsonValueDictToAny(_ dictionary: [String: JSONValue]) -> [String: Any] {
    dictionary.mapValues(jsonValueToAny)
}

func friendlyDecodingError(_ error: Error, root: String) -> String {
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

        if name.contains("Dictionary") || name.contains("JSONObject") { return "object" }
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
