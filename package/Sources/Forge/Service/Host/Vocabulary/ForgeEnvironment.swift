//
//  ForgeEnvironment.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp
import WarpStandard

struct ForgeEnvironment: ConcurrentEnvironment {
    // MARK: - Property
    let capabilities: CapabilitySet
    let dispatcher: any RunDispatching
    let pool: WorkflowPool
    let runID: String
    let rootID: String
    let origin: DispatchOrigin

    // Where the run's native verbs announce their steps.
    let bridge: EventBridge

    // MARK: - Initializer
    init(
        capabilities: CapabilitySet,
        dispatcher: any RunDispatching,
        pool: WorkflowPool,
        runID: String,
        rootID: String,
        origin: DispatchOrigin,
        bridge: EventBridge
    ) {
        self.capabilities = capabilities
        self.dispatcher = dispatcher
        self.pool = pool
        self.runID = runID
        self.rootID = rootID
        self.origin = origin
        self.bridge = bridge
    }

    // MARK: - Lifecycle
    // A piece of a fan-out speaks to no agent session it did not open.
    func isolateConcurrentWork<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async throws -> T {
        try await AgentSession.$current.withValue(nil) {
            try await work()
        }
    }

    // MARK: - Public
    static func from<P: NativeProcedure>(_ invocation: Invocation<P>) throws -> ForgeEnvironment {
        guard let environment = invocation.environment as? ForgeEnvironment else {
            throw ExecutionError(
                "'\(invocation.selector)' needs the forge environment"
                    + " — run it through the forge executor"
            )
        }

        return environment
    }

    // The daemon's step-concurrency ceiling: resource-heavy actions (shell,
    // agent) acquire a pool slot for their whole run — acquisition also marks
    // the run as running, which is what run-state observation reads.
    func withStepSlot<T: Sendable>(
        _ body: () async throws -> T
    ) async throws -> T {
        try await pool.acquireStepSlot(runID: runID)

        do {
            let result = try await body()

            await pool.releaseStepSlot(runID: runID)

            return result
        } catch {
            await pool.releaseStepSlot(runID: runID)

            throw error
        }
    }

    // MARK: - Private
}

func withDeadline<T: Sendable>(
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

            throw DeadlineExceeded(seconds: seconds)
        }

        guard let first = try await group.next() else {
            throw ExecutionError("deadline group finished without a result")
        }

        group.cancelAll()

        return first
    }
}
