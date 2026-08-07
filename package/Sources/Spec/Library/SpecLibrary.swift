//
//  SpecLibrary.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// The language's standard vocabulary, kept apart from the language itself —
// Swift's kernel doesn't know `count` or `contains`; Foundation does. The core
// owns structure (steps, scopes, resolution, is/is_not/one_of/present as the
// language's `==`); the library owns the words, and hosts extend it.
public struct SpecLibrary: Sendable {
    // MARK: - Property
    public static let standard = try! SpecLibrary(
        derivations: [
            Derivation(key: "count") { value in
                switch value {
                case .array(let array):
                    return .int(array.count)

                case .string(let string):
                    return .int(string.count)

                case .object(let object):
                    return .int(object.count)

                default:
                    return nil
                }
            }
        ],
        atoms: [
            PredicateAtom(key: "contains") { resolved, operand, path in
                guard let resolved else { return false }

                switch resolved {
                case .string(let text):
                    guard case .string(let part) = operand else {
                        throw ReferenceUnfit(
                            path: path,
                            reason: "contains asks a non-string part of a string"
                        )
                    }

                    return text.contains(part)

                case .array(let elements):
                    return elements.contains { element in element.matches(operand) }

                default:
                    throw ReferenceUnfit(
                        path: path,
                        reason: "contains asks \(resolved.typeName), expected string or array"
                    )
                }
            },
            PredicateAtom(
                key: "starts_with",
                validate: { operand in
                    guard case .string = operand else {
                        throw TemplateSyntaxError("starts_with needs a string prefix")
                    }
                },
                evaluate: { resolved, operand, path in
                    guard let resolved else { return false }

                    guard case .string(let prefix) = operand else { return false }

                    guard case .string(let text) = resolved else {
                        throw ReferenceUnfit(
                            path: path,
                            reason: "starts_with asks \(resolved.typeName), expected string"
                        )
                    }

                    return text.hasPrefix(prefix)
                }
            ),
            PredicateAtom(
                key: "regex",
                validate: { operand in
                    guard
                        case .string(let pattern) = operand,
                        (try? NSRegularExpression(pattern: pattern)) != nil
                    else {
                        throw TemplateSyntaxError("regex needs a valid string pattern")
                    }
                },
                evaluate: { resolved, operand, path in
                    guard let resolved else { return false }

                    guard case .string(let pattern) = operand else { return false }

                    guard case .string(let text) = resolved else {
                        throw ReferenceUnfit(
                            path: path,
                            reason: "regex asks \(resolved.typeName), expected string"
                        )
                    }

                    return text.range(of: pattern, options: .regularExpression) != nil
                }
            )
        ]
    )

    public private(set) var derivations: [String: Derivation]
    public private(set) var atoms: [String: PredicateAtom]

    // MARK: - Initializer
    public init(derivations: [Derivation] = [], atoms: [PredicateAtom] = []) throws {
        self.derivations = [:]
        self.atoms = [:]

        for derivation in derivations {
            try insert(derivation)
        }

        for atom in atoms {
            try insert(atom)
        }
    }

    // MARK: - Public
    public func deriving(_ derivation: Derivation) throws -> SpecLibrary {
        var library = self

        try library.insert(derivation)

        return library
    }

    public func asking(_ atom: PredicateAtom) throws -> SpecLibrary {
        var library = self

        try library.insert(atom)

        return library
    }

    // MARK: - Private
    // A word is claimed once, through one door — the registration policy lives
    // here, not in whichever entry point happened to be called.
    private mutating func insert(_ derivation: Derivation) throws {
        guard derivations[derivation.key] == nil else {
            throw ValidationError(
                "derivation '\(derivation.key)' is already registered"
            )
        }

        derivations[derivation.key] = derivation
    }

    private mutating func insert(_ atom: PredicateAtom) throws {
        guard !Condition.reservedOperatorKeys.contains(atom.key) else {
            throw ValidationError(
                "atom key '\(atom.key)' is reserved by the condition core"
            )
        }

        guard atoms[atom.key] == nil else {
            throw ValidationError(
                "atom '\(atom.key)' is already registered"
            )
        }

        atoms[atom.key] = atom
    }
}
