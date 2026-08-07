//
//  Parameter.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public struct Parameter: Sendable, Equatable {
    public enum Shape: String, Sendable, Codable, CaseIterable {
        case string
        case int
        case double
        case bool
        case object
        case array
    }

    // MARK: - Property
    public let type: Shape
    public let oneOf: [String]?
    public let `default`: Value?
    public let hint: String?

    // A parameter without a default is required — optionality has no separate axis.
    public var isRequired: Bool { `default` == nil }

    // MARK: - Initializer
    public init(
        type: Shape,
        oneOf: [String]? = nil,
        default: Value? = nil,
        hint: String? = nil
    ) {
        self.type = type
        self.oneOf = oneOf
        self.default = `default`
        self.hint = hint
    }

    // MARK: - Public
    public func taking(_ value: Value, called name: String) throws -> Value {
        guard value != .null else {
            guard let fallback = self.default else {
                throw InputValidationError("input '\(name)': required, and nothing was given")
            }

            return fallback
        }

        return try checking(value, called: name)
    }

    public func checking(_ value: Value, called name: String) throws -> Value {
        if value == .null {
            guard self.default == .null else {
                throw InputValidationError(
                    "input '\(name)': expected \(type.rawValue), got null"
                )
            }

            return value
        }

        // Settling means the inside reads the declared type — a passing value is
        // normalized to the declared representation, not just waved through.
        let settled: Value?

        switch (type, value) {
        case (.string, .string), (.bool, .bool), (.int, .int),
            (.double, .double), (.object, .object), (.array, .array):
            settled = value

        case (.int, .double(let double)):
            settled = Int(exactly: double).map(Value.int)

        case (.double, .int(let integer)):
            settled = .double(Double(integer))

        default:
            settled = nil
        }

        guard let settled else {
            throw InputValidationError(
                "input '\(name)': expected \(type.rawValue), got \(value.typeName)"
            )
        }

        if let allowed = oneOf {
            let scalar = Self.scalar(settled)

            guard let scalar, allowed.contains(scalar) else {
                throw InputValidationError(
                    "input '\(name)': '\(scalar ?? settled.typeName)' not in oneOf \(allowed)"
                )
            }
        }

        return settled
    }

    // MARK: - Private
    private static func scalar(_ value: Value) -> String? {
        switch value {
        case .string(let string):
            return string

        case .int(let integer):
            return String(integer)

        case .bool(let bool):
            return String(bool)

        case .double(let double):
            return Int(exactly: double).map(String.init) ?? String(double)

        default:
            return nil
        }
    }
}

extension Parameter: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case oneOf
        case `default`
        case hint
    }

    public init(from decoder: Decoder) throws {
        if
            let single = try? decoder.singleValueContainer().decode(String.self),
            let shape = Shape(rawValue: single)
        {
            self.type = shape
            self.oneOf = nil
            self.default = nil
            self.hint = nil

            return
        }

        try KeyGate.rejectUnknownKeys(in: decoder, known: CodingKeys.self, context: "input param")

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Shape.self, forKey: .type)
        let oneOf = try container.decodeIfPresent([String].self, forKey: .oneOf)
        let written = container.contains(.default)
            ? try container.decode(Value.self, forKey: .default)
            : nil
        let hint = try container.decodeIfPresent(String.self, forKey: .hint)

        self.type = type
        self.oneOf = oneOf
        self.hint = hint

        // A declaration's own default passes the same gate a caller's value would,
        // and what is stored is the settled result — otherwise a default-supplied
        // slot would read a different type than a caller-supplied one.
        if let written, written != .null {
            let name = decoder.codingPath.last?.stringValue ?? "?"
            let probe = Parameter(type: type, oneOf: oneOf, hint: hint)

            do {
                self.default = try probe.checking(written, called: "\(name).default")
            } catch {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "\(error)")
                )
            }
        } else {
            self.default = written
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(oneOf, forKey: .oneOf)
        try container.encodeIfPresent(`default`, forKey: .default)
        try container.encodeIfPresent(hint, forKey: .hint)
    }
}
