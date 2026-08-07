//
//  ForgeHost.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

struct ForgeHost: Sendable {
    // MARK: - Property
    let shell: any ShellExecuting
    let agent: any AgentServing
    let dispatcher: any RunDispatching
    let resources: any ResourceReading
    let loader: SpecLoader
    let pool: WorkflowPool
    let runID: String

    // MARK: - Initializer
    init(
        shell: any ShellExecuting,
        agent: any AgentServing,
        dispatcher: any RunDispatching,
        resources: any ResourceReading,
        loader: SpecLoader,
        pool: WorkflowPool,
        runID: String
    ) {
        self.shell = shell
        self.agent = agent
        self.dispatcher = dispatcher
        self.resources = resources
        self.loader = loader
        self.pool = pool
        self.runID = runID
    }

    // MARK: - Public
    static func from(_ context: ActionContext) throws -> ForgeHost {
        guard let host = context.environment as? ForgeHost else {
            throw ExecutionError(
                "step '\(context.stepID)' needs the forge host environment"
                    + " — run it through the forge executor"
            )
        }

        return host
    }

    // The daemon's step-concurrency ceiling: resource-heavy actions (shell,
    // agent) acquire a pool slot for their whole run — acquisition also marks
    // the run as running, which is what run-state observation reads.
    func withStepSlot<T: Sendable>(
        _ body: () async throws -> T
    ) async throws -> T {
        try await pool.acquireStepSlot(workflowID: runID)

        do {
            let result = try await body()

            await pool.releaseStepSlot(workflowID: runID)

            return result
        } catch {
            await pool.releaseStepSlot(workflowID: runID)

            throw error
        }
    }

    // MARK: - Private
}

// The parallel boundary severs the ambient agent session — concurrent children
// must not share one conversation. A child that needs a session opens its own
// `invoke` inside the branch.
extension ForgeHost: Spec.ParallelIsolating {
    func isolateParallelChild<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        try await WorkflowExecutionState.$agentSession.withValue(nil) {
            try await body()
        }
    }
}

// forge's world failures carry the kernel's rescue stamp — a nonzero exit or a
// failed child run is the world answering, not the author mistyping. The host
// also owns each failure's vocabulary as a rescue-visible value: the kernel
// binds these payloads under the failed step's id while its rescue runs.
extension BackendNonzeroExit: Spec.RecoverableFailure {
    var payload: Spec.Value {
        .object([
            "type": .string("nonzero_exit"),
            "message": .string(message),
            "exit_code": .int(Int(exitCode)),
            "stderr": .string(stderr),
            "stdout": .string(stdout)
        ])
    }
}

extension ChildRunFailed: Spec.RecoverableFailure {
    var payload: Spec.Value {
        .object(["type": .string("child_run_failed"), "message": .string(message)])
    }
}

// A step deadline races the body against the clock — the world running late is
// a recoverable failure, so a rescue can answer it.
func withHostDeadline<T: Sendable>(
    seconds: Double?,
    body: @escaping @Sendable () async throws -> T
) async throws -> T {
    guard let seconds else { return try await body() }

    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await body()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))

            throw HostTimeout(seconds: seconds)
        }

        guard let first = try await group.next() else {
            throw ExecutionError("deadline group finished without a result")
        }

        group.cancelAll()

        return first
    }
}
