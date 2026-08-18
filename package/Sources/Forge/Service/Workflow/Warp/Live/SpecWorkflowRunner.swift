//
//  SpecWorkflowRunner.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// The run-level driver over the language's executor — the daemon-facing frame
// Warp deliberately does not own: run identity, tokens, the work registry,
// pool slots, run started/completed/failed events and the child-run boundary.
// It also IS the dispatch seam: a `dispatch` step asks the daemon for an
// isolated run, and every entrance (RPC method, scheduler, child step) walks
// through the same `dispatch(module:...)` door — authz, pool registration,
// log adoption — before a run begins.
actor SpecWorkflowRunner {
    // MARK: - Property
    let catalog: SpecCatalog
    let eventBus: WorkflowEventBus
    let policyStore: PolicyStore
    let pool: WorkflowPool
    let workRegistry: WorkRegistry
    let tokenAuthority: TokenAuthority
    let jobStore: JobStore?
    let shell: any ShellExecuting
    let agent: any AgentServing
    let resources: any ResourceReading

    // MARK: - Initializer
    init(
        catalog: SpecCatalog,
        eventBus: WorkflowEventBus,
        policyStore: PolicyStore,
        pool: WorkflowPool,
        workRegistry: WorkRegistry,
        tokenAuthority: TokenAuthority,
        jobStore: JobStore? = nil,
        shell: any ShellExecuting,
        agent: any AgentServing,
        resources: any ResourceReading
    ) {
        self.catalog = catalog
        self.eventBus = eventBus
        self.policyStore = policyStore
        self.pool = pool
        self.workRegistry = workRegistry
        self.tokenAuthority = tokenAuthority
        self.jobStore = jobStore
        self.shell = shell
        self.agent = agent
        self.resources = resources
    }

    // MARK: - Public
    static func newRunID() -> String { "wf-\(UUID().uuidString.prefix(8))" }

    // The one dispatch door: policy, pool registration and log adoption happen
    // here for every caller — RPC, scheduler and child steps alike.
    func dispatch(
        module: Warp.Module,
        name: String,
        inputs: [String: JSONValue],
        principal: String,
        origin: DispatchOrigin,
        rootID: String? = nil,
        parentNodeID: String? = nil,
        parentRunID: String? = nil,
        parameters: [String: JSONValue]? = nil,
        correlator: String? = nil,
        workflowID: String? = nil,
        mode: DispatchMode
    ) async throws -> WorkflowRunResult {
        try await DispatchAuthz.requireDispatch(
            principal: principal,
            workflow: name,
            policyStore: policyStore,
            context: "dispatch"
        )

        let runID = workflowID ?? Self.newRunID()

        try await pool.register(
            workflowID: runID,
            workflowName: name,
            rootID: rootID ?? runID,
            origin: origin,
            principal: principal
        )

        let result = await LogContext.adoptRun(
            runID: runID,
            parentRootID: rootID,
            parentNodeID: parentNodeID,
            parentRunID: parentRunID
        ) {
            await LogContext.$asyncDispatch.withValue(mode.isUnawaited) {
                await LogContext.$parameters.withValue(parameters) {
                    await run(
                        module: module,
                        name: name,
                        inputs: inputs,
                        origin: origin,
                        principal: principal,
                        parameters: parameters,
                        correlator: correlator,
                        workflowID: runID
                    )
                }
            }
        }

        await pool.unregister(workflowID: runID)

        return result
    }

    // MARK: - Private
    // Every run enters through `dispatch` — pool admission and identity live
    // there, once; this frame owns tokens, registry and event framing.
    private func run(
        module: Warp.Module,
        name: String,
        inputs: [String: JSONValue] = [:],
        origin: DispatchOrigin = .manual,
        principal: String? = nil,
        parameters: [String: JSONValue]? = nil,
        correlator: String? = nil,
        workflowID: String? = nil
    ) async -> WorkflowRunResult {
        let runID = workflowID ?? Self.newRunID()
        let context = WorkflowExecutionContext(
            workflowID: runID,
            workflowName: name,
            origin: origin
        )
        let principal = principal ?? "cli:\(name)"
        let claims = TokenClaims(principal: principal, workflowID: runID)
        let token = tokenAuthority.mint(claims)

        await workRegistry.register(WorkRecord(
            workflowID: runID,
            workflowName: name,
            principal: principal,
            origin: origin,
            rootID: LogContext.rootID,
            nodeID: LogContext.nodeID,
            correlator: correlator,
            parameters: parameters
        ))

        let result = await LogContext.$workflowContext.withValue(context) {
            await LogContext.$parameters.withValue(parameters) {
                await WorkflowExecutionState.$accessToken.withValue(token) {
                    await WorkflowExecutionState.$accessTokenID.withValue(claims.id) {
                        await runBody(
                            module: module,
                            name: name,
                            inputs: inputs,
                            origin: origin,
                            runID: runID
                        )
                    }
                }
            }
        }

        await workRegistry.beginClose(workflowID: runID)

        if let jobStore {
            await jobStore.closeRun(
                run: claims.id,
                failure: result.status == .failed
                    ? (result.error.map { failure in "\(failure.type): \(failure.message)" }
                        ?? "failed")
                    : nil
            )
        }

        await workRegistry.release(workflowID: runID)

        return result
    }

    private func runBody(
        module: Warp.Module,
        name: String,
        inputs: [String: JSONValue],
        origin: DispatchOrigin,
        runID: String
    ) async -> WorkflowRunResult {
        let started = ContinuousClock.now
        let (inputPreview, inputLength) = inputs.isEmpty
            ? (nil, nil)
            : Self.valuePreview(.object(inputs))

        await eventBus.publish(WorkflowEvent(
            kind: .workflowStarted,
            workflowID: runID,
            workflowName: name,
            origin: origin,
            parameters: LogContext.parameters,
            inputs: inputs.isEmpty ? nil : inputs,
            inputPreview: inputPreview,
            inputLen: inputLength
        ))

        let originScope: [String: Warp.Value] = {
            var scope: [String: Warp.Value] = ["kind": .string(origin.kind)]

            if let originID = origin.id { scope["id"] = .string(originID) }

            return scope
        }()

        let runScope: [String: Warp.Value] = [
            "workflow_id": .string(runID),
            "root_id": .string(LogContext.rootID ?? runID)
        ]
        let eventBus = self.eventBus
        let environment = ForgeEnvironment(
            shell: shell,
            agent: agent,
            dispatcher: self,
            resources: resources,
            loader: catalog.loader,
            pool: pool,
            runID: runID
        )
        let executor = catalog.loader.language.makeExecutor(
            catalog: catalog,
            observer: EventBridge(
                workflowID: runID,
                workflowName: name,
                publish: { event in await eventBus.publish(event) }
            ),
            environment: environment
        )

        do {
            // Linking is inside the do-block on purpose: a workflow naming a
            // sibling that has left the catalog is a run that failed, and it
            // reports through the same ledger a failed step does.
            // Every workflow the daemon can see goes into the link, and the
            // name this run was asked for is the entry — `gcc *.yaml`, then
            // start from one symbol.
            //
            // The module being dispatched leads, and any catalog copy declaring
            // that same name is left out: normally it *is* that copy, and when
            // it is not (an inline spec) the caller's is the one they meant.
            // Two copies would be a duplicate symbol, which is right in general
            // and wrong for exactly this case.
            let world = await catalog.modules().filter { module in
                module.procedures[name] == nil
            }
            // The entry is named qualified where the module has a name, because
            // a bare name is ambiguous the moment anything else declares it —
            // and forge's own verbs do: a workflow called `agent` is a real
            // thing to want, and `forge.agent` should not take the name from it.
            let image = try catalog.loader.language.link(
                [module] + world + ForgeSpec.linkables,
                entry: module.name.map { owner in "\(owner).\(name)" } ?? name
            )
            let outputs = try await withCancelSignal(runID: runID) {
                try await executor.run(
                    image,
                    arguments: inputs.mapValues { value in ValueBridge.value(value) }
                        .merging([
                            "origin": .object(originScope),
                            "run": .object(runScope)
                        ]) { _, ambient in ambient }
                )
            }
            // A run answers one value; this notation's `outputs:` lowers to a
            // record, so the fields of that record are what a workflow reports.
            let jsonOutputs: [String: JSONValue]

            if case .object(let fields) = outputs {
                jsonOutputs = fields.mapValues { value in ValueBridge.json(value) }
            } else {
                jsonOutputs = [:]
            }
            let duration = (ContinuousClock.now - started).milliseconds

            await eventBus.publish(WorkflowEvent(
                kind: .workflowCompleted,
                workflowID: runID,
                workflowName: name,
                origin: origin,
                outputs: jsonOutputs,
                durationMs: duration
            ))

            return WorkflowRunResult(
                workflowID: runID,
                workflowName: name,
                status: .ok,
                outputs: jsonOutputs,
                durationMs: duration,
                error: nil
            )
        } catch {
            let duration = (ContinuousClock.now - started).milliseconds
            let (errorType, errorMessage) = Self.errorPair(error)

            await eventBus.publish(WorkflowEvent(
                kind: .workflowFailed,
                workflowID: runID,
                workflowName: name,
                origin: origin,
                errorType: errorType,
                errorMessage: errorMessage,
                durationMs: duration
            ))

            return WorkflowRunResult(
                workflowID: runID,
                workflowName: name,
                status: .failed,
                outputs: [:],
                durationMs: duration,
                error: .init(
                    kind: Self.failureKind(of: error),
                    type: errorType,
                    message: errorMessage
                )
            )
        }
    }

    private func withCancelSignal<T: Sendable>(
        runID: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let pool = self.pool

        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                await pool.awaitCancellation(workflowID: runID)

                throw CancellationError()
            }

            defer { group.cancelAll() }

            guard let first = try await group.next() else {
                throw CancellationError()
            }

            return first
        }
    }

    static func valuePreview(_ value: JSONValue) -> (String?, Int?) {
        let previewLimit = 2000

        if case .null = value { return (nil, nil) }

        let text: String

        if case .string(let string) = value {
            text = string
        } else {
            let data = (try? JSONEncoder().encode(value)) ?? Data()

            text = String(decoding: data, as: UTF8.self)
        }

        let length = text.count
        let preview = length > previewLimit ? String(text.prefix(previewLimit)) : text

        return (preview, length)
    }

    private static func errorPair(_ error: any Error) -> (String, String) {
        if let forgeError = error as? ForgeError {
            return (forgeError.wireType, forgeError.message)
        }

        return (String(describing: type(of: error)), String(describing: error))
    }

    private static func failureKind(of error: any Error) -> WorkflowRunResult.RunFailure.Kind {
        if error is CancellationError { return .cancelled }
        if error is any WorkFailure { return .work }
        if error is any Warp.RecoverableFailure { return .work }

        return .fault
    }
}

// A `dispatch` step lands here — resolved against the daemon catalog (or
// lowered from the inline body the loader admitted at load time), then walked
// through the same dispatch door as any RPC caller.
extension SpecWorkflowRunner: RunDispatching {
    func dispatch(
        name: String?,
        inline: Warp.Value?,
        inputs: [String: Warp.Value]
    ) async throws -> Warp.Value {
        let module: Warp.Module
        let childName: String

        if let name {
            switch await catalog.resolve(name) {
            case .found(let found):
                module = found

            case .invalid(let reason):
                throw WorkflowValidationError(
                    "dispatch: workflow '\(name)' is broken — \(reason)"
                )

            case .unobserved(let reason):
                throw ResolutionError(
                    "dispatch: workflow '\(name)' could not be resolved — \(reason)"
                )

            case .missing:
                throw DispatchTargetNotFound("dispatch: workflow '\(name)' not found")
            }

            childName = name
        } else {
            guard let inline else {
                throw ProtocolError("dispatch: neither name nor inline spec (decoder gap)")
            }

            // Same shape the RPC door admits: an inline spec is one procedure.
            childName = WorkflowDispatchMethod.inlineSigil
            module = Warp.Module(
                procedures: [
                    childName: try catalog.loader
                        .procedure(from: ForgeSpec.seeding(procedure: inline))
                ]
            )
        }

        let parentName = LogContext.workflowContext?.workflowName ?? "unknown"

        if let parentRunID = LogContext.workflowContext?.workflowID {
            await pool.markStarted(workflowID: parentRunID)
        }

        let result = try await dispatch(
            module: module,
            name: childName,
            inputs: inputs.mapValues { value in ValueBridge.json(value) },
            principal: "cli:\(parentName)",
            origin: .manual,
            rootID: LogContext.rootID,
            parentNodeID: LogContext.nodeID,
            parentRunID: LogContext.workflowContext?.workflowID,
            parameters: LogContext.parameters,
            mode: .awaited
        )

        switch result.status {
        case .ok:
            return .object(result.outputs.mapValues { value in ValueBridge.value(value) })

        case .failed:
            guard let failure = result.error else {
                throw ProtocolError("dispatch '\(childName)' failed (no error detail)")
            }

            let summary = "dispatch '\(childName)' failed: \(failure.type) — \(failure.message)"

            switch failure.kind {
            case .work:
                throw ChildRunFailed(summary)

            case .fault:
                throw ChildRunFaulted(summary)

            case .cancelled:
                throw ChildRunCancelled(
                    "dispatch '\(childName)' cancelled: \(failure.message)"
                )
            }
        }
    }
}
