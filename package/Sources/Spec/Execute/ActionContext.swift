//
//  ActionContext.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public struct ActionContext: Sendable {
    // MARK: - Property
    public let stepID: String
    public let scope: Scope

    public var resolver: Resolver { resolver(for: scope) }

    private let executor: Executor

    // MARK: - Initializer
    init(stepID: String, scope: Scope, executor: Executor) {
        self.stepID = stepID
        self.scope = scope
        self.executor = executor
    }

    // MARK: - Property (services)
    // The host services this run was configured with — an opaque bag the
    // language never reads. Host actions downcast it to reach their runtime
    // (process spawner, agent backend, daemons); kernel actions ignore it.
    public var environment: (any Sendable)? { executor.environment }

    // MARK: - Public
    public func resolver(for scope: Scope) -> Resolver {
        Resolver(scope: scope, library: executor.library)
    }

    public func run(_ steps: [Step], in scope: Scope) async throws -> StepsResult {
        try await executor.run(steps, in: scope)
    }

    public func run(spec name: String, inputs: [String: Value]) async throws -> [String: Value] {
        guard let store = executor.store else {
            throw ExecutionError(
                "step '\(stepID)' uses spec '\(name)' but no SpecStore was provided"
            )
        }

        // Spec-to-spec calls carry no termination guard — a name reappearing in the
        // call chain is not an oracle for a cycle (recursion over shrinking input is
        // legitimate), and a depth budget is policy, not mechanism. Runaway calls
        // are the host's concern: observation and cancellation, which propagate
        // here through task cancellation.
        let spec = try await store.spec(named: name)

        return try await executor.run(spec, inputs: inputs, contexts: scope.contexts)
    }

    // MARK: - Private
}
