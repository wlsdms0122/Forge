//
//  Signature.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

public struct Signature: Sendable, Equatable {
    // MARK: - Property
    public let parameters: [String: Parameter]

    // MARK: - Initializer
    public init(parameters: [String: Parameter] = [:]) {
        self.parameters = parameters
    }

    // MARK: - Public
    // Inputs settle once at the scope boundary — inside the scope, references read
    // the settled values instead of re-evaluating.
    public func settle(_ given: [String: Value]) throws -> [String: Value] {
        let undeclared = given.keys
            .filter { name in parameters[name] == nil }
            .sorted()

        guard undeclared.isEmpty else {
            throw InputValidationError(
                "inputs: not declared in the signature:"
                    + " \(undeclared.joined(separator: ", "))"
            )
        }

        let missing = parameters
            .filter { name, parameter in
                parameter.isRequired && (given[name] ?? .null) == .null
            }
            .keys
            .sorted()

        guard missing.isEmpty else {
            throw InputValidationError(
                "inputs: required, and nothing was given for \(missing.joined(separator: ", "))"
            )
        }

        // The settled scope is built from the declaration, never copied from the
        // caller — only declared names exist inside the boundary.
        var settled: [String: Value] = [:]

        for (name, parameter) in parameters.sorted(by: { left, right in left.key < right.key }) {
            settled[name] = try parameter.taking(given[name] ?? .null, called: name)
        }

        return settled
    }

    // MARK: - Private
}

extension Signature: Codable {
    public init(from decoder: Decoder) throws {
        self.parameters = try decoder.singleValueContainer()
            .decode([String: Parameter].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        try container.encode(parameters)
    }
}
