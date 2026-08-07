//
//  GroupAction.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// A named sub-scope — steps run together and the group speaks with one output.
// forge spelled this `invoke { steps }`, enact `group { body }`; the kernel owns
// the structure under one name.
public struct GroupAction: Action {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case steps
        case output
    }

    // MARK: - Property
    public static let key = "group"

    public let steps: [Step]
    public let output: Reference?

    public var scopeDeclarations: [ScopeDeclaration] {
        [ScopeDeclaration(
            label: "group",
            steps: steps,
            trailingPaths: output?.referencedPaths ?? []
        )]
    }

    // MARK: - Initializer
    public init(steps: [Step], output: Reference? = nil) {
        self.steps = steps
        self.output = output
    }

    public init(from decoder: Decoder) throws {
        try KeyGate.rejectUnknownKeys(in: decoder, known: CodingKeys.self, context: "group")

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.steps = try container.decode([Step].self, forKey: .steps)
        self.output = try container.decodeIfPresent(Reference.self, forKey: .output)
    }

    // MARK: - Public
    public func run(_ context: ActionContext) async throws -> Value {
        let result = try await context.run(steps, in: context.scope)

        // A sequence speaks with its last statement unless an explicit output
        // says otherwise — the same rule rescue follows.
        guard let output else { return result.lastOutput }

        return try context.resolver(for: result.scope).resolve(output)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(steps, forKey: .steps)
        try container.encodeIfPresent(output, forKey: .output)
    }

    // MARK: - Private
}
