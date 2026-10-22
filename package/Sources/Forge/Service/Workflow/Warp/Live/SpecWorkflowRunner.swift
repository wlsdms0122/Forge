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

        let eventBus = self.eventBus
        let environment = ForgeEnvironment(
            shell: shell,
            agent: agent,
            dispatcher: self,
            resources: resources,
            pool: pool,
            runID: runID,
            rootID: LogContext.rootID ?? runID,
            origin: origin
        )
        let executor = Warp.Executor(
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
            // name this run was asked for is the entry.
            //
            // The module being dispatched leads, and any catalog copy declaring
            // that same name is left out: normally it *is* that copy, and when
            // it is not (an inline spec) the caller's is the one they meant.
            // Two copies would be a duplicate symbol, which is right in general
            // and wrong for exactly this case.
            let entry = try Name(name)
            let world = await catalog.modules().filter { module in
                module.procedures[entry] == nil
            }
            let image = try await Builder().build([module] + world + ForgeSpec.linkables())
            let arguments = try Self.arguments(
                inputs,
                for: module.procedures[entry]?.signature
            )
            let outputs = try await withCancelSignal(runID: runID) {
                try await executor.run(image, entry: entry, arguments: arguments)
            }
            // A run returns one value, and the fields of the struct or map a
            // workflow returns are what it reports.
            let jsonOutputs = try ValueBridge.fields(outputs).mapValues(ValueBridge.json)
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

    // The inputs a caller handed, by name, and null for every optional
    // parameter it left out: the language takes every argument from its
    // caller, and a caller that holds nothing there says so.
    private static func arguments(
        _ inputs: [String: JSONValue],
        for signature: Signature?
    ) throws -> [Name: Warp.Value] {
        var arguments: [Name: Warp.Value] = [:]

        for (name, value) in inputs {
            arguments[try Name(name)] = try ValueBridge.value(value)
        }

        for parameter in signature?.parameters ?? [] where arguments[parameter.name] == nil {
            guard case .nullable = parameter.type else { continue }

            arguments[parameter.name] = .null
        }

        return arguments
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
    func dispatch(name: String, inputs: [String: Warp.Value]) async throws -> Warp.Value {
        let module: Warp.Module

        switch await catalog.resolve(name) {
        case let .found(found):
            module = found

        case let .invalid(reason):
            throw WorkflowValidationError(
                "dispatch: workflow '\(name)' is broken — \(reason)"
            )

        case let .unobserved(reason):
            throw ResolutionError(
                "dispatch: workflow '\(name)' could not be resolved — \(reason)"
            )

        case .missing:
            throw DispatchTargetNotFound("dispatch: workflow '\(name)' not found")
        }

        let parentName = LogContext.workflowContext?.workflowName ?? "unknown"

        if let parentRunID = LogContext.workflowContext?.workflowID {
            await pool.markStarted(workflowID: parentRunID)
        }

        let result = try await dispatch(
            module: module,
            name: name,
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
            return try ValueBridge.value(.object(result.outputs))

        case .failed:
            guard let failure = result.error else {
                throw ProtocolError("dispatch '\(name)' failed (no error detail)")
            }

            let summary = "dispatch '\(name)' failed: \(failure.type) — \(failure.message)"

            switch failure.kind {
            case .work:
                throw ChildRunFailed(summary)

            case .fault:
                throw ChildRunFaulted(summary)

            case .cancelled:
                throw ChildRunCancelled(
                    "dispatch '\(name)' cancelled: \(failure.message)"
                )
            }
        }
    }
}
