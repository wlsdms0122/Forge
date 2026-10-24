//
//  WorkflowRunner.swift
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
// through the same `dispatch(_:...)` door — authorization, pool registration,
// log adoption — before a run begins.
actor WorkflowRunner {
    // MARK: - Property
    let catalog: WorkflowCatalog
    let eventBus: WorkflowEventBus
    let policyStore: PolicyStore
    let pool: WorkflowPool
    let workRegistry: WorkRegistry
    let tokenAuthority: TokenAuthority
    let jobStore: JobStore?
    let capabilities: CapabilitySet

    // MARK: - Initializer
    init(
        catalog: WorkflowCatalog,
        eventBus: WorkflowEventBus,
        policyStore: PolicyStore,
        pool: WorkflowPool,
        workRegistry: WorkRegistry,
        tokenAuthority: TokenAuthority,
        jobStore: JobStore? = nil,
        capabilities: CapabilitySet
    ) {
        self.catalog = catalog
        self.eventBus = eventBus
        self.policyStore = policyStore
        self.pool = pool
        self.workRegistry = workRegistry
        self.tokenAuthority = tokenAuthority
        self.jobStore = jobStore
        self.capabilities = capabilities
    }

    // MARK: - Public
    static func newRunID() -> String { "wf-\(UUID().uuidString.prefix(8))" }

    // The one dispatch door: policy, pool registration and log adoption happen
    // here for every caller — RPC, scheduler and child steps alike.
    func dispatch(
        _ workflow: Workflow,
        inputs: [String: JSONValue],
        principal: String,
        origin: DispatchOrigin,
        rootID: String? = nil,
        parentNodeID: String? = nil,
        parentRunID: String? = nil,
        parameters: [String: JSONValue]? = nil,
        correlator: String? = nil,
        runID: String? = nil,
        mode: DispatchMode
    ) async throws -> WorkflowRunResult {
        let name = workflow.name

        try await DispatchAuthorization.requireDispatch(
            principal: principal,
            workflow: name,
            policyStore: policyStore,
            context: "dispatch"
        )

        let runID = runID ?? Self.newRunID()

        try await pool.register(
            runID: runID,
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
                        workflow,
                        inputs: inputs,
                        origin: origin,
                        principal: principal,
                        parameters: parameters,
                        correlator: correlator,
                        runID: runID
                    )
                }
            }
        }

        await pool.unregister(runID: runID)

        return result
    }

    // MARK: - Private
    // Every run enters through `dispatch` — pool admission and identity live
    // there, once; this frame owns tokens, registry and event framing.
    private func run(
        _ workflow: Workflow,
        inputs: [String: JSONValue] = [:],
        origin: DispatchOrigin = .manual,
        principal: String? = nil,
        parameters: [String: JSONValue]? = nil,
        correlator: String? = nil,
        runID: String? = nil
    ) async -> WorkflowRunResult {
        let name = workflow.name
        let runID = runID ?? Self.newRunID()
        let context = WorkflowExecutionContext(
            runID: runID,
            workflowName: name,
            origin: origin
        )
        let principal = principal ?? "cli:\(name)"
        let claims = TokenClaims(principal: principal, runID: runID)
        let token = tokenAuthority.mint(claims)

        await workRegistry.register(WorkRecord(
            runID: runID,
            workflowName: name,
            principal: principal,
            origin: origin,
            rootID: LogContext.rootID,
            nodeID: LogContext.nodeID,
            correlator: correlator,
            parameters: parameters
        ))

        let result = await WorkflowExecutionState.$context.withValue(context) {
            await LogContext.$metadata.withValue(LogPayload(context.asPayload)) {
                await LogContext.$parameters.withValue(parameters) {
                    await WorkflowExecutionState.$accessToken.withValue(token) {
                        await runBody(
                            workflow,
                            inputs: inputs,
                            origin: origin,
                            runID: runID
                        )
                    }
                }
            }
        }

        await workRegistry.beginClose(runID: runID)

        if let jobStore {
            await jobStore.closeRun(
                run: claims.id,
                failure: result.status == .failed
                    ? (result.error.map { failure in "\(failure.object.type): \(failure.object.message)" }
                        ?? "failed")
                    : nil
            )
        }

        await workRegistry.release(runID: runID)

        return result
    }

    private func runBody(
        _ workflow: Workflow,
        inputs: [String: JSONValue],
        origin: DispatchOrigin,
        runID: String
    ) async -> WorkflowRunResult {
        let name = workflow.name
        let started = ContinuousClock.now
        let (inputPreview, inputLength) = inputs.isEmpty
            ? (nil, nil)
            : Self.valuePreview(.object(inputs))

        await eventBus.publish(WorkflowEvent(
            kind: .workflowStarted,
            runID: runID,
            workflowName: name,
            origin: origin,
            parameters: LogContext.parameters,
            inputs: inputs.isEmpty ? nil : inputs,
            inputPreview: inputPreview,
            inputLen: inputLength
        ))

        let eventBus = self.eventBus

        do {
            // Linking is inside the do-block on purpose: a workflow naming a
            // sibling that has left the catalog is a run that failed, and it
            // reports through the same ledger a failed step does. The catalog
            // links the module beside every workflow that built, and the name
            // this run was asked for is the entry.
            let entry = try Name(name)
            let image = try await catalog.image(running: workflow.module, entry: entry)
            let environment = ForgeEnvironment(
                capabilities: capabilities,
                dispatcher: self,
                pool: pool,
                runID: runID,
                rootID: LogContext.rootID ?? runID,
                origin: origin,
                bridge: EventBridge(
                    runID: runID,
                    workflowName: name,
                    verbs: catalog.vocabulary.verbs,
                    publish: { event in await eventBus.publish(event) }
                )
            )
            let executor = Executor(environment: environment)
            let arguments = try Self.arguments(
                inputs,
                for: workflow.module.procedures[entry]?.signature
            )
            let outputs = try await withCancelSignal(runID: runID) {
                try await executor.run(image, entry: entry, arguments: arguments)
            }
            let jsonOutputs = Self.outputs(of: outputs)
            let duration = (ContinuousClock.now - started).milliseconds

            await eventBus.publish(WorkflowEvent(
                kind: .workflowCompleted,
                runID: runID,
                workflowName: name,
                origin: origin,
                outputs: jsonOutputs,
                durationMs: duration
            ))

            return WorkflowRunResult(
                runID: runID,
                workflowName: name,
                status: .ok,
                outputs: jsonOutputs,
                durationMs: duration,
                error: nil
            )
        } catch {
            // A run's task cancelled (a schedule dropped, the daemon stopping,
            // a client gone) is a cancelled run, whichever child of the
            // cancel signal's group throws first.
            let error = error is CancellationError
                ? RunCancelled("run '\(runID)' was cancelled")
                : error
            let duration = (ContinuousClock.now - started).milliseconds
            let failure = ErrorObject(failure: error)

            await eventBus.publish(WorkflowEvent(
                kind: .workflowFailed,
                runID: runID,
                workflowName: name,
                origin: origin,
                errorType: failure.type,
                errorMessage: failure.message,
                durationMs: duration
            ))

            return WorkflowRunResult(
                runID: runID,
                workflowName: name,
                status: .failed,
                outputs: [:],
                durationMs: duration,
                error: .init(kind: Self.failureKind(of: error), object: failure)
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
                await pool.awaitCancellation(runID: runID)

                throw RunCancelled("run '\(runID)' was cancelled")
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
            guard case .optional = parameter.type else { continue }

            arguments[parameter.name] = .null
        }

        return arguments
    }

    // What a run reports for the value it returned: the fields of a struct or
    // the entries of a map, nothing for null, and any other value under
    // `result`, so every workflow the build accepts reports what it returns.
    private static func outputs(of returned: Warp.Value) -> [String: JSONValue] {
        switch ValueBridge.json(returned) {
        case .null:
            return [:]

        case let .object(fields):
            return fields

        case let other:
            return ["result": other]
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

    private static func failureKind(of error: any Error) -> WorkflowRunResult.RunFailure.Kind {
        if error is RunCancelled { return .cancelled }
        if error is any WorkFailure { return .work }
        if error is any Warp.RecoverableFailure { return .work }

        return .fault
    }
}

// A `dispatch` step lands here: resolved against the daemon catalog, then
// walked through the same dispatch door as any RPC caller.
extension WorkflowRunner: RunDispatching {
    func dispatch(name: String, inputs: [String: Warp.Value]) async throws -> Warp.Value {
        let workflow = try await catalog.workflow(named: name)

        let parentName = WorkflowExecutionState.context?.workflowName ?? "unknown"

        if let parentRunID = WorkflowExecutionState.context?.runID {
            await pool.markStarted(runID: parentRunID)
        }

        let result = try await dispatch(
            workflow,
            inputs: inputs.mapValues { value in ValueBridge.json(value) },
            principal: "cli:\(parentName)",
            origin: .manual,
            rootID: LogContext.rootID,
            parentNodeID: LogContext.nodeID,
            parentRunID: WorkflowExecutionState.context?.runID,
            parameters: LogContext.parameters,
            mode: .awaited
        )

        guard let failure = result.error else {
            return try ValueBridge.value(.object(result.outputs))
        }

        let summary = "dispatch '\(name)' failed: \(failure.object.type) — \(failure.object.message)"

        switch failure.kind {
        case .work:
            throw ChildRunFailed(summary)

        case .fault:
            throw ChildRunFaulted(summary)

        case .cancelled:
            throw ChildRunCancelled(
                "dispatch '\(name)' cancelled: \(failure.object.message)"
            )
        }
    }
}
