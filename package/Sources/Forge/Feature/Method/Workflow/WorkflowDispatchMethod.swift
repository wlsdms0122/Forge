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
        let runID: String
        let origin: DispatchOrigin
        let rootID: String?
        let parentNodeID: String?
        let parentRunID: String?
        let parameters: [String: JSONValue]?
        let correlator: String?

        var effectiveRootID: String { rootID ?? runID }

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let runner: WorkflowRunner
    let catalog: WorkflowCatalog
    let workRegistry: WorkRegistry

    // MARK: - Initializer
    init(
        runner: WorkflowRunner,
        catalog: WorkflowCatalog,
        workRegistry: WorkRegistry
    ) {
        self.runner = runner
        self.catalog = catalog
        self.workRegistry = workRegistry
    }

    // MARK: - Public
    func prepare(_ request: RPCRequest, claims: TokenClaims) async throws -> Prepared {
        let principal = claims.principal
        let record = try await workRegistry.requireLiveRecord(
            runID: claims.runID,
            context: "workflow.dispatch"
        )
        let workflow = try await resolveProgram(request.params)
        let inputs = request.params["inputs"]?.objectValue ?? [:]
        let runID = WorkflowRunner.newRunID()
        let rootID: String?
        let parentNodeID: String?
        let parentRunID: String?
        let correlator: String?
        let parameters: [String: JSONValue]?
        let origin: DispatchOrigin

        if let record {
            rootID      = record.rootID
            parentNodeID = record.nodeID
            parentRunID  = record.runID
            correlator   = record.correlator
            parameters   = record.parameters
            origin      = DispatchOrigin(kind: "workflow", id: record.runID)
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
            runID: runID,
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
            inputs: try prepared.inputs.mapValues(ValueBridge.value),
            principal: prepared.principal,
            origin: prepared.origin,
            rootID: prepared.rootID,
            parentNodeID: prepared.parentNodeID,
            parentRunID: prepared.parentRunID,
            parameters: prepared.parameters,
            correlator: prepared.correlator,
            runID: prepared.runID,
            mode: mode
        )
    }

    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONValue {
        let prepared = try await prepare(request, claims: claims)
        let isAsync = request.params["async"]?.boolValue ?? false
        let principal = prepared.principal
        let runID = prepared.runID

        if !isAsync {
            return try await runDispatch(prepared, mode: .awaited).jsonValue
        } else {
            try await DispatchAuthorization.requireDispatch(
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
                            "run_id": runID,
                            "principal":   principal,
                            "error":       String(describing: error),
                        ]),
                        level: .error,
                        category: "workflow"
                    )
                }
            }

            return [
                "run_id": .string(runID),
                "name":        .string(workflowName),
                "status":      "running"
            ]
        }
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
                return try await catalog.inline(.object(spec))
            } catch {
                throw ProtocolError("workflow.dispatch: malformed 'spec': \(error)")
            }
        }

        if let name = params["name"]?.stringValue, !name.isEmpty {
            return try await catalog.workflow(named: name)
        }

        throw ProtocolError("workflow.dispatch: one of 'spec' or 'name' is required")
    }
}
