//
//  BranchAction.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

public struct BranchAction: Action {
    public struct Arm: Sendable, Codable {
        private enum CodingKeys: String, CodingKey, CaseIterable {
            case steps
            case output
        }

        // MARK: - Property
        public let steps: [Step]
        public let output: Reference?

        // MARK: - Initializer
        public init(steps: [Step], output: Reference? = nil) {
            self.steps = steps
            self.output = output
        }

        public init(from decoder: Decoder) throws {
            try KeyGate.rejectUnknownKeys(
                in: decoder,
                known: CodingKeys.self,
                context: "branch arm"
            )

            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.steps = try container.decode([Step].self, forKey: .steps)
            self.output = try container.decodeIfPresent(Reference.self, forKey: .output)
        }

        // MARK: - Public
        // MARK: - Private
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case when
        case then
        case `else`
    }

    // MARK: - Property
    public static let key = "branch"

    public let when: Condition
    public let then: Arm
    public let `else`: Arm?

    public var scopeDeclarations: [ScopeDeclaration] {
        var scopes = [
            ScopeDeclaration(
                label: "branch.then.steps",
                steps: then.steps,
                trailingPaths: then.output?.referencedPaths ?? []
            )
        ]

        if let elseArm = `else` {
            scopes.append(ScopeDeclaration(
                label: "branch.else.steps",
                steps: elseArm.steps,
                trailingPaths: elseArm.output?.referencedPaths ?? []
            ))
        }

        return scopes
    }

    public var referencedPaths: [[PathSegment]] { when.referencedPaths }

    // MARK: - Initializer
    public init(when: Condition, then: Arm, else: Arm? = nil) {
        self.when = when
        self.then = then
        self.else = `else`
    }

    public init(from decoder: Decoder) throws {
        try KeyGate.rejectUnknownKeys(in: decoder, known: CodingKeys.self, context: "branch")

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.when = try container.decode(Condition.self, forKey: .when)
        self.then = try container.decode(Arm.self, forKey: .then)
        self.else = try container.decodeIfPresent(Arm.self, forKey: .else)
    }

    // MARK: - Public
    public func run(_ context: ActionContext) async throws -> Value {
        let take = try context.resolver.evaluate(when)

        guard let arm = take ? then : `else` else { return .null }

        let result = try await context.run(arm.steps, in: context.scope)

        guard let output = arm.output else { return .null }

        return try context.resolver(for: result.scope).resolve(output)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(when, forKey: .when)
        try container.encode(then, forKey: .then)
        try container.encodeIfPresent(`else`, forKey: .else)
    }

    // MARK: - Private
}
