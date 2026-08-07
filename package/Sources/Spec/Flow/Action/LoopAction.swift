//
//  LoopAction.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// The world ends this repetition — the body runs while `where` holds, like a
// `while` loop; the language does not prevent an author's infinite loop any more
// than Swift does. An optional `guard` declares an iteration budget when the
// author wants one, and runaway protection beyond that (deadlines, observation,
// cancellation) is the host's concern. Iterating over material the spec already
// holds is `each`, whose structure guarantees termination without a budget.
public struct LoopAction: Action {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case `where`
        case steps
        case `guard`
        case output
    }

    // MARK: - Property
    public static let key = "loop"

    public let `where`: Condition
    public let steps: [Step]
    public let `guard`: Int?
    public let output: Reference?

    public var scopeDeclarations: [ScopeDeclaration] {
        [ScopeDeclaration(
            label: "loop",
            steps: steps,
            bindsOwnID: true,
            trailingPaths: output?.referencedPaths ?? []
        )]
    }

    public var referencedPaths: [[PathSegment]] { `where`.referencedPaths }

    public var referencesOwnID: Bool { true }

    // MARK: - Initializer
    public init(where: Condition, steps: [Step], guard: Int? = nil, output: Reference? = nil) {
        self.where = `where`
        self.steps = steps
        self.guard = `guard`
        self.output = output
    }

    public init(from decoder: Decoder) throws {
        try KeyGate.rejectUnknownKeys(in: decoder, known: CodingKeys.self, context: "loop")

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.where = try container.decode(Condition.self, forKey: .where)
        self.steps = try container.decode([Step].self, forKey: .steps)
        self.guard = try container.decodeIfPresent(Int.self, forKey: .guard)
        self.output = try container.decodeIfPresent(Reference.self, forKey: .output)

        if let budget = self.guard, budget <= 0 {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "loop `guard` must be a positive iteration budget"
                )
            )
        }
    }

    // MARK: - Public
    public func run(_ context: ActionContext) async throws -> Value {
        var scope = context.scope
        var round = 0

        while true {
            scope = scope.binding(context.stepID, to: .object(["index": .int(round)]))

            let take = try context.resolver(for: scope).evaluate(`where`)

            if !take {
                guard let output else { return .null }

                return try context.resolver(for: scope).resolve(output)
            }

            if let limit = `guard`, round >= limit {
                throw LoopGuardExceeded(stepID: context.stepID, limit: limit)
            }

            scope = try await context.run(steps, in: scope).scope
            round += 1
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(`where`, forKey: .where)
        try container.encode(steps, forKey: .steps)
        try container.encodeIfPresent(`guard`, forKey: .guard)
        try container.encodeIfPresent(output, forKey: .output)
    }

    // MARK: - Private
}
