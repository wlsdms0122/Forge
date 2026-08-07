//
//  ParallelAction.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// each's concurrent twin — a map over static branches instead of a static list.
// Children run concurrently, each against a copy of the parent scope; no scope
// merge exists, so siblings cannot see each other and the step speaks with one
// value: an object of child outputs keyed by child id.
//
// Failure composition follows the rescue stamp: if every failed child failed
// recoverably the composite is recoverable, and one author mistake makes the
// whole step an author mistake — a rescue must not absorb a typo because a
// sibling happened to time out.
public struct ParallelAction: Action {
    // MARK: - Property
    public static let key = "parallel"

    public let steps: [Step]

    public var scopeDeclarations: [ScopeDeclaration] {
        steps.map { step in
            ScopeDeclaration(label: "parallel.\(step.id)", steps: [step])
        }
    }

    // MARK: - Initializer
    // The invariants live on the one designated initializer — however a value is
    // constructed, decoded or programmatic, the same rules hold.
    public init(steps: [Step]) throws {
        guard !steps.isEmpty else {
            throw ValidationError("parallel needs at least one child step")
        }

        let ids = steps.map(\.id)

        guard Set(ids).count == ids.count else {
            throw ValidationError(
                "parallel children must have distinct ids; got: \(ids)"
            )
        }

        self.steps = steps
    }

    public init(from decoder: Decoder) throws {
        let steps = try decoder.singleValueContainer().decode([Step].self)

        do {
            try self.init(steps: steps)
        } catch {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "\(error)")
            )
        }
    }

    // MARK: - Public
    public func run(_ context: ActionContext) async throws -> Value {
        let results = await withTaskGroup(
            of: (String, Result<Value, any Error>).self
        ) { group in
            let isolating = context.environment as? any ParallelIsolating

            for step in steps {
                group.addTask {
                    let child: @Sendable () async throws -> Value = {
                        try await context.run([step], in: context.scope).lastOutput
                    }

                    do {
                        if let isolating {
                            return (step.id, .success(try await isolating.isolateParallelChild(child)))
                        }

                        return (step.id, .success(try await child()))
                    } catch {
                        return (step.id, .failure(error))
                    }
                }
            }

            var collected: [String: Result<Value, any Error>] = [:]

            for await (id, result) in group {
                collected[id] = result
            }

            return collected
        }

        var outputs: [String: Value] = [:]
        var failures: [String: any Error] = [:]

        for (id, result) in results {
            switch result {
            case .success(let output):
                outputs[id] = output

            case .failure(let error):
                failures[id] = error
            }
        }

        guard failures.isEmpty else {
            // Deterministic by child id — a dictionary walk must not decide which
            // author mistake gets reported.
            let ordered = failures.sorted { left, right in left.key < right.key }

            if let authorMistake = ordered.first(where: { _, error in
                !(error is any RecoverableFailure)
            }) {
                throw authorMistake.value
            }

            throw ParallelFailed(failures: failures.mapValues { error in "\(error)" })
        }

        return .object(outputs)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        try container.encode(steps)
    }

    // MARK: - Private
}
