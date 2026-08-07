//
//  UseAction.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// Calls another spec against its signature — inputs settle at the callee's
// boundary, and the callee's outputs come back as this step's output object.
public struct UseAction: Action {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case spec
        case inputs
    }

    // MARK: - Property
    public static let key = "use"

    public let spec: String
    public let inputs: [String: Reference]

    public var referencedPaths: [[PathSegment]] {
        inputs.values.flatMap(\.referencedPaths)
    }

    // MARK: - Initializer
    public init(spec: String, inputs: [String: Reference] = [:]) {
        self.spec = spec
        self.inputs = inputs
    }

    public init(from decoder: Decoder) throws {
        try KeyGate.rejectUnknownKeys(in: decoder, known: CodingKeys.self, context: "use")

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.spec = try container.decode(String.self, forKey: .spec)
        self.inputs = try container.decodeIfPresent(
            [String: Reference].self,
            forKey: .inputs
        ) ?? [:]
    }

    // MARK: - Public
    public func run(_ context: ActionContext) async throws -> Value {
        let resolver = context.resolver
        let settled = try inputs.mapValues { reference in try resolver.resolve(reference) }
        let outputs = try await context.run(spec: spec, inputs: settled)

        return .object(outputs)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(spec, forKey: .spec)

        if !inputs.isEmpty { try container.encode(inputs, forKey: .inputs) }
    }

    // MARK: - Private
}
