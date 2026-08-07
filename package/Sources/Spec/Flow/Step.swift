//
//  Step.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

public struct Step: Sendable {
    // MARK: - Property
    public let id: String
    public let when: Condition?
    public let rescue: [Step]?
    public let action: any Action

    public var actionKey: String { type(of: action).key }

    // MARK: - Initializer
    public init(
        id: String,
        when: Condition? = nil,
        rescue: [Step]? = nil,
        action: any Action
    ) {
        self.id = id
        self.when = when
        self.rescue = rescue
        self.action = action
    }

    // MARK: - Public
    // MARK: - Private
}

extension Step: Codable {
    private enum EnvelopeKeys: String, CodingKey, CaseIterable {
        case id
        case when
        case rescue
    }

    private struct AnyKey: CodingKey {
        // MARK: - Property
        let stringValue: String

        var intValue: Int? { nil }

        // MARK: - Initializer
        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }

        // MARK: - Public
        // MARK: - Private
    }

    public init(from decoder: Decoder) throws {
        guard let registry = decoder.userInfo[.actionRegistry] as? ActionRegistry else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "step decoding requires an ActionRegistry"
                        + " — decode through SpecLoader"
                )
            )
        }

        try KeyGate.rejectUnknownKeys(
            in: decoder,
            known: EnvelopeKeys.allCases.map(\.stringValue) + registry.keys,
            context: "step"
        )

        let envelope = try decoder.container(keyedBy: EnvelopeKeys.self)

        self.id = try envelope.decode(String.self, forKey: .id)
        self.when = try envelope.decodeIfPresent(Condition.self, forKey: .when)
        self.rescue = try envelope.decodeIfPresent([Step].self, forKey: .rescue)

        let container = try decoder.container(keyedBy: AnyKey.self)
        let found = registry.keys.filter { key in
            container.contains(AnyKey(stringValue: key))
        }

        guard found.count == 1, let key = found.first else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "a step must declare exactly one action key"
                        + " (\(registry.keys.joined(separator: "/")));"
                        + " found: \(found)"
                )
            )
        }

        guard let actionType = registry.actionType(for: key) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "no action registered for key '\(key)'"
                )
            )
        }

        self.action = try actionType.init(
            from: container.superDecoder(forKey: AnyKey(stringValue: key))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var envelope = encoder.container(keyedBy: EnvelopeKeys.self)

        try envelope.encode(id, forKey: .id)
        try envelope.encodeIfPresent(when, forKey: .when)
        try envelope.encodeIfPresent(rescue, forKey: .rescue)

        var container = encoder.container(keyedBy: AnyKey.self)

        try action.encode(to: container.superEncoder(forKey: AnyKey(stringValue: actionKey)))
    }
}
