//
//  WorkflowRunner.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// Runs a workflow on the language's executor and owns what a run is to the
// daemon: its identity, its token, the work registry, its pool slot, its
// started, completed and failed events, and the boundary of a child run. Every
// entrance (RPC method, scheduler, a `dispatch` step) comes in through
// `dispatch(_:...)`, which authorizes, registers in the pool and adopts the
// log before a run begins.
actor WorkflowRunner {
    // MARK: - Property
    let workflows: WorkflowReader
    let eventBus: WorkflowEventBus
    let policyStore: PolicyStore
    let pool: WorkflowPool
    let workRegistry: WorkRegistry
    let tokenAuthority: TokenAuthority
    let jobStore: JobStore?
    let capabilities: CapabilitySet

    // MARK: - Initializer
    init(
        workflows: WorkflowReader,
        eventBus: WorkflowEventBus,
        policyStore: PolicyStore,
        pool: WorkflowPool,
        workRegistry: WorkRegistry,
        tokenAuthority: TokenAuthority,
        jobStore: JobStore? = nil,
        capabilities: CapabilitySet
    ) {
        self.workflows = workflows
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
    // here for every caller (RPC, scheduler and child steps alike).
    func dispatch(
        _ workflow: Workflow,
        inputs: [String: Warp.Value],
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
        let path = workflow.path

        try await DispatchAuthorization.requireDispatch(
            principal: principal,
            workflow: path,
            policyStore: policyStore,
            context: "dispatch"
        )

        let runID = runID ?? Self.newRunID()

        try await pool.register(
            runID: runID,
            workflowName: path,
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
    // Every run enters through `dispatch`: pool admission and identity live
    // there, once; this frame owns tokens, registry and event framing.
    private func run(
        _ workflow: Workflow,
        inputs: [String: Warp.Value] = [:],
        origin: DispatchOrigin = .manual,
        principal: String? = nil,
        parameters: [String: JSONValue]? = nil,
        correlator: String? = nil,
        runID: String? = nil
    ) async -> WorkflowRunResult {
        let path = workflow.path
        let runID = runID ?? Self.newRunID()
        let context = WorkflowExecutionContext(
            runID: runID,
            workflowName: path,
            origin: origin
        )
        let principal = principal ?? "cli:\(path)"
        let claims = TokenClaims(principal: principal, runID: runID)
        let token = tokenAuthority.mint(claims)

        await workRegistry.register(WorkRecord(
            runID: runID,
            workflowName: path,
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
            let failure: String? = switch result.outcome {
            case .returned:
                nil

            case let .failed(failure):
                "\(failure.object.type): \(failure.object.message)"
            }

            await jobStore.closeRun(run: claims.id, failure: failure)
        }

        await workRegistry.release(runID: runID)

        return result
    }

    private func runBody(
        _ workflow: Workflow,
        inputs: [String: Warp.Value],
        origin: DispatchOrigin,
        runID: String
    ) async -> WorkflowRunResult {
        let path = workflow.path
        let started = ContinuousClock.now

        await eventBus.publish(WorkflowEvent(
            kind: .workflowStarted,
            runID: runID,
            workflowName: path,
            origin: origin,
            parameters: LogContext.parameters,
            inputs: inputs.isEmpty ? nil : try? inputs.mapValues(ValueBridge.json)
        ))

        let eventBus = self.eventBus

        do {
            // Building is inside the do-block on purpose: an inline spec that
            // does not build is a run that failed, and it reports through the
            // same ledger a failed step does.
            let entry = try Name(Workflow.entry)
            let image = try await workflows.image(of: workflow)
            let environment = ForgeEnvironment(
                capabilities: capabilities,
                dispatcher: self,
                pool: pool,
                runID: runID,
                rootID: LogContext.rootID ?? runID,
                origin: origin,
                bridge: EventBridge(
                    runID: runID,
                    workflowName: path,
                    verbs: workflows.vocabulary.verbs,
                    publish: { event in await eventBus.publish(event) }
                )
            )
            let executor = Executor(environment: environment)
            let arguments = try Self.arguments(
                inputs,
                for: workflow.module.procedures[entry]?.signature
            )
            let returned = try await withCancelSignal(runID: runID) {
                try await executor.run(image, entry: entry, arguments: arguments)
            }
            let output = try ValueBridge.json(returned)
            let duration = (ContinuousClock.now - started).milliseconds

            await eventBus.publish(WorkflowEvent(
                kind: .workflowCompleted,
                runID: runID,
                workflowName: path,
                origin: origin,
                output: output,
                durationMs: duration
            ))

            return WorkflowRunResult(
                runID: runID,
                workflowName: path,
                outcome: .returned(returned),
                durationMs: duration
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
                workflowName: path,
                origin: origin,
                errorType: failure.type,
                errorMessage: failure.message,
                durationMs: duration
            ))

            return WorkflowRunResult(
                runID: runID,
                workflowName: path,
                outcome: .failed(.init(kind: Self.failureKind(of: error), object: failure)),
                durationMs: duration
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
        _ inputs: [String: Warp.Value],
        for signature: Signature?
    ) throws -> [Name: Warp.Value] {
        var arguments: [Name: Warp.Value] = [:]

        for (name, value) in inputs {
            arguments[try Name(name)] = value
        }

        for parameter in signature?.parameters ?? [] where arguments[parameter.name] == nil {
            guard case .optional = parameter.type else { continue }

            arguments[parameter.name] = .null
        }

        return arguments
    }

    private static func failureKind(of error: any Error) -> WorkflowRunResult.RunFailure.Kind {
        if error is RunCancelled { return .cancelled }
        if error is any WorkFailure { return .work }
        if error is any Warp.RecoverableFailure { return .work }

        return .fault
    }
}

// A `dispatch` step lands here: the workflow read at its path, then
// walked through the same dispatch door as any RPC caller.
extension WorkflowRunner: RunDispatching {
    func dispatch(path: String, inputs: [String: Warp.Value]) async throws -> Warp.Value {
        let workflow = try await workflows.workflow(at: path)

        let parentName = WorkflowExecutionState.context?.workflowName ?? "unknown"

        if let parentRunID = WorkflowExecutionState.context?.runID {
            await pool.markStarted(runID: parentRunID)
        }

        let result = try await dispatch(
            workflow,
            inputs: inputs,
            principal: "cli:\(parentName)",
            origin: .manual,
            rootID: LogContext.rootID,
            parentNodeID: LogContext.nodeID,
            parentRunID: WorkflowExecutionState.context?.runID,
            parameters: LogContext.parameters,
            mode: .awaited
        )

        switch result.outcome {
        case let .returned(value):
            return value

        case let .failed(failure):
            let summary = "dispatch '\(path)' failed: \(failure.object.type): \(failure.object.message)"

            switch failure.kind {
            case .work:
                throw ChildRunFailed(summary)

            case .fault:
                throw ChildRunFaulted(summary)

            case .cancelled:
                throw ChildRunCancelled(
                    "dispatch '\(path)' cancelled: \(failure.object.message)"
                )
            }
        }
    }
}
