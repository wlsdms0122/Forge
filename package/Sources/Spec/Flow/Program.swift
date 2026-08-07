//
//  Spec.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

public struct Program: Sendable {
    // MARK: - Property
    // Metadata only — the kernel does not derive spec identity from it. Identity
    // is the store key the caller resolved the spec by.
    public let name: String?
    public let description: String?

    // Absent `inputs:` means an empty signature, not an absent contract — a spec
    // that declares nothing takes nothing, so a stray caller input is rejected
    // instead of leaking into scope.
    public let inputs: Signature
    public let steps: [Step]
    public let outputs: [String: Reference]?

    // MARK: - Initializer
    public init(
        name: String? = nil,
        description: String? = nil,
        inputs: Signature = Signature(),
        steps: [Step],
        outputs: [String: Reference]? = nil
    ) {
        self.name = name
        self.description = description
        self.inputs = inputs
        self.steps = steps
        self.outputs = outputs
    }

    // MARK: - Public
    // MARK: - Private
}

extension Program: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case name
        case description
        case inputs
        case steps
        case outputs
    }

    public init(from decoder: Decoder) throws {
        try KeyGate.rejectUnknownKeys(in: decoder, known: CodingKeys.self, context: "spec")

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.inputs = try container.decodeIfPresent(Signature.self, forKey: .inputs)
            ?? Signature()
        self.steps = try container.decode([Step].self, forKey: .steps)
        self.outputs = try container.decodeIfPresent(
            [String: Reference].self,
            forKey: .outputs
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)

        if !inputs.parameters.isEmpty { try container.encode(inputs, forKey: .inputs) }

        try container.encode(steps, forKey: .steps)
        try container.encodeIfPresent(outputs, forKey: .outputs)
    }
}
