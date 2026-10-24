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
        let workflow = try await resolveProgram(request.params)
        let inputs = request.params["inputs"]?.objectValue ?? [:]
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
            let rootField = request.params["root"]
            rootID      = rootField?["root_id"]?.stringValue
            parentNodeID = rootField?["parent_id"]?.stringValue
            parentRunID  = nil
            correlator   = request.params["correlator"]?.stringValue
            parameters   = request.params["parameters"]?.objectValue

            if let originField = request.params["origin"],
                let kind = originField["kind"]?.stringValue {
                origin = DispatchOrigin(kind: kind, id: originField["id"]?.stringValue)
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

    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONValue {
        let prepared = try await prepare(request, claims: claims)
        let isAsync = request.params["async"]?.boolValue ?? false
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
                "workflow_id": .string(workflowID),
                "name":        .string(workflowName),
                "status":      "running"
            ]
        }
    }

    func encodeResult(_ result: WorkflowRunResult) -> JSONValue {
        var object: [String: JSONValue] = [
            "workflow_id": .string(result.workflowID),
            "name":        .string(result.workflowName),
            "status":      "ok",
            "duration_ms": .int(result.durationMs),
            "outputs":     .object(result.outputs)
        ]

        if let failure = result.error {
            object["status"] = "failed"
            object["error"] = failure.object.jsonValue
        }

        return .object(object)
    }

    // MARK: - Private
    private func resolveProgram(
        _ params: [String: JSONValue]
    ) async throws -> Workflow {
        if let spec = params["spec"]?.objectValue {
            guard spec["name"] == nil else {
                throw ProtocolError("workflow.dispatch: inline 'spec' must be anonymous — a 'name' key is not allowed (the name is fixed to '\(WorkflowCatalog.inlineSigil)')")
            }

            do {
                return try await store.inline(.object(spec))
            } catch {
                throw ProtocolError("workflow.dispatch: malformed 'spec' — \(error)")
            }
        }

        if let name = params["name"]?.stringValue, !name.isEmpty {
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
