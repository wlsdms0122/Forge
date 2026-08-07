//
//  Executor.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

public struct Executor: Sendable {

    // MARK: - Property
    public let store: (any SpecStore)?
    public let observer: (any ExecutionObserver)?
    public let library: SpecLibrary
    public let environment: (any Sendable)?

    // MARK: - Initializer
    public init(
        store: (any SpecStore)? = nil,
        observer: (any ExecutionObserver)? = nil,
        library: SpecLibrary = .standard,
        environment: (any Sendable)? = nil
    ) {
        self.store = store
        self.observer = observer
        self.library = library
        self.environment = environment
    }

    // MARK: - Public
    public func run(
        _ spec: Program,
        inputs: [String: Value] = [:],
        contexts: [String: [String: Value]] = [:]
    ) async throws -> [String: Value] {
        let settled = try spec.inputs.settle(inputs)
        let scope = Scope(inputs: settled, contexts: contexts, library: library)
        let outcome = try await run(spec.steps, in: scope)

        guard let outputs = spec.outputs else { return [:] }

        let resolver = Resolver(scope: outcome.scope, library: library)

        return try outputs.mapValues { reference in try resolver.resolve(reference) }
    }

    // MARK: - Private
    func run(_ steps: [Step], in startScope: Scope) async throws -> StepsResult {
        // The cancellation check sits at sequence entry, not only per step — an
        // empty body inside a loop round must still observe cancellation, or the
        // host's one lever against a runaway loop silently stops working.
        try Task.checkCancellation()

        var scope = startScope
        var lastOutput = Value.null

        for step in steps {
            try Task.checkCancellation()

            let output = try await runStep(step, in: scope)

            scope = scope.binding(step.id, to: output)
            lastOutput = output
        }

        return StepsResult(scope: scope, lastOutput: lastOutput)
    }

    private func runStep(_ step: Step, in scope: Scope) async throws -> Value {
        if let when = step.when {
            let take = try Resolver(scope: scope, library: library).evaluate(when)

            guard take else {
                await observer?.stepSkipped(id: step.id)

                return .null
            }
        }

        await observer?.stepStarted(id: step.id, action: step.actionKey)

        do {
            let output = try await step.action.run(
                ActionContext(stepID: step.id, scope: scope, executor: self)
            )

            await observer?.stepCompleted(id: step.id, output: output, rescued: false)

            return output
        } catch {
            await observer?.stepFailed(id: step.id, error: error)

            guard !Task.isCancelled else { throw error }
            guard
                let failure = error as? any RecoverableFailure,
                let rescue = step.rescue
            else {
                throw error
            }

            // While the rescue runs, the failure is a value under the failed
            // step's id — readable, never leaking: the id is rebound to the
            // rescue's output the moment the rescue answers.
            let outcome = try await run(
                rescue,
                in: scope.binding(step.id, to: failure.payload)
            )

            await observer?.stepCompleted(
                id: step.id,
                output: outcome.lastOutput,
                rescued: true
            )

            return outcome.lastOutput
        }
    }
}
