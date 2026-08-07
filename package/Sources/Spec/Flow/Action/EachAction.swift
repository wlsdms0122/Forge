//
//  EachAction.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// The material ends this repetition — one round per element, so termination is
// structural and no iteration budget exists. Each round exposes
// ${<step-id>.item} / ${<step-id>.index}; with `output`, the per-round results
// collect into the step's output array.
public struct EachAction: Action {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case `in`
        case steps
        case output
    }

    // MARK: - Property
    public static let key = "each"

    public let `in`: Reference
    public let steps: [Step]
    public let output: Reference?

    public var scopeDeclarations: [ScopeDeclaration] {
        [ScopeDeclaration(
            label: "each",
            steps: steps,
            bindsOwnID: true,
            trailingPaths: output?.referencedPaths ?? []
        )]
    }

    public var referencedPaths: [[PathSegment]] { `in`.referencedPaths }

    // MARK: - Initializer
    public init(in reference: Reference, steps: [Step], output: Reference? = nil) {
        self.in = reference
        self.steps = steps
        self.output = output
    }

    public init(from decoder: Decoder) throws {
        try KeyGate.rejectUnknownKeys(in: decoder, known: CodingKeys.self, context: "each")

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.in = try container.decode(Reference.self, forKey: .in)
        self.steps = try container.decode([Step].self, forKey: .steps)
        self.output = try container.decodeIfPresent(Reference.self, forKey: .output)
    }

    // MARK: - Public
    public func run(_ context: ActionContext) async throws -> Value {
        let material = try context.resolver.resolve(`in`)

        guard case .array(let elements) = material else {
            // A plain ref names its own locus; any other expression shape has
            // no path to point at, so the step carries the blame instead of an
            // empty `{ ref: }` rendering.
            guard let path = `in`.refPath else {
                throw ExecutionError(
                    "each `in` (step '\(context.stepID)') resolved to"
                        + " \(material.typeName), expected array"
                )
            }

            throw ReferenceUnfit(
                path: path,
                reason: "each `in` is \(material.typeName), expected array"
            )
        }

        var scope = context.scope
        var collected: [Value] = []

        for (index, element) in elements.enumerated() {
            scope = scope.binding(
                context.stepID,
                to: .object(["item": element, "index": .int(index)])
            )
            scope = try await context.run(steps, in: scope).scope

            if let output {
                collected.append(try context.resolver(for: scope).resolve(output))
            }
        }

        guard output != nil else { return .null }

        return .array(collected)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(`in`, forKey: .in)
        try container.encode(steps, forKey: .steps)
        try container.encodeIfPresent(output, forKey: .output)
    }

    // MARK: - Private
}
