//
//  Condition.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// A predicate is `{ of: <expression>, <operator>: <expression> }` — exactly two
// keys, both sides full expressions, so a condition can compare a reference
// against another reference, not only against a literal. The unary `present`
// takes its subject directly: `present: <expression>`.
public indirect enum Condition: Sendable {
    case predicate(of: Reference, operator: Operator, operand: Reference?)
    case allOf([Condition])
    case anyOf([Condition])
    case not(Condition)

    // The core operators are the language's equality and existence — everything
    // else is vocabulary, addressed by library atom name.
    public enum Operator: Sendable, Equatable {
        case `is`
        case isNot
        case oneOf
        case present
        case atom(String)
    }

    // MARK: - Property
    public var referencedPaths: [[PathSegment]] {
        switch self {
        case .predicate(let subject, _, let operand):
            return subject.referencedPaths + (operand?.referencedPaths ?? [])

        case .allOf(let conditions), .anyOf(let conditions):
            return conditions.flatMap(\.referencedPaths)

        case .not(let condition):
            return condition.referencedPaths
        }
    }

    // MARK: - Initializer
    // MARK: - Public
    // The condition core's own spellings — a library atom may not claim these.
    // Derived from the decoder's own tables so the gate and the grammar cannot
    // drift apart.
    public static let reservedOperatorKeys = Set(
        combinatorKeys + coreOperators.map(\.key) + [subjectKey]
    )

    // MARK: - Private
}

extension Condition: Codable {
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

    static let subjectKey = "of"
    static let combinatorKeys = ["all_of", "any_of", "not"]
    static let coreOperators: [(key: String, operator: Operator)] = [
        ("is", .is),
        ("is_not", .isNot),
        ("one_of", .oneOf),
        ("present", .present)
    ]

    public init(from decoder: Decoder) throws {
        let library = decoder.userInfo[.specLibrary] as? SpecLibrary ?? .standard
        let operatorKeys = Self.combinatorKeys
            + Self.coreOperators.map(\.key)
            + library.atoms.keys.sorted()

        try KeyGate.rejectUnknownKeys(
            in: decoder,
            known: operatorKeys + [Self.subjectKey],
            context: "condition"
        )

        let container = try decoder.container(keyedBy: AnyKey.self)
        let found = operatorKeys.filter { key in
            container.contains(AnyKey(stringValue: key))
        }

        guard found.count == 1, let key = found.first else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "condition requires exactly one operator key"
                        + " (\(operatorKeys.joined(separator: " / ")));"
                        + " found: \(found)"
                )
            )
        }

        let hasSubject = container.contains(AnyKey(stringValue: Self.subjectKey))

        switch key {
        case "all_of", "any_of", "not":
            guard !hasSubject else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: container.codingPath,
                        debugDescription: "`of` does not accompany \(key) —"
                            + " combinators take conditions, not a subject"
                    )
                )
            }

        case "present":
            // Unary — the subject rides directly under the operator key.
            guard !hasSubject else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: container.codingPath,
                        debugDescription: "present takes its expression directly —"
                            + " `present: <expression>`, without `of`"
                    )
                )
            }

        default:
            guard hasSubject else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: container.codingPath,
                        debugDescription: "\(key) needs a subject —"
                            + " { of: <expression>, \(key): <expression> }"
                    )
                )
            }
        }

        switch key {
        case "all_of":
            self = .allOf(try container.decode(
                [Condition].self,
                forKey: AnyKey(stringValue: key)
            ))

            return

        case "any_of":
            self = .anyOf(try container.decode(
                [Condition].self,
                forKey: AnyKey(stringValue: key)
            ))

            return

        case "not":
            self = .not(try container.decode(
                Condition.self,
                forKey: AnyKey(stringValue: key)
            ))

            return

        case "present":
            self = .predicate(
                of: try container.decode(
                    Reference.self,
                    forKey: AnyKey(stringValue: key)
                ),
                operator: .present,
                operand: nil
            )

            return

        default:
            break
        }

        let subject = try container.decode(
            Reference.self,
            forKey: AnyKey(stringValue: Self.subjectKey)
        )
        let operand = try container.decode(
            Reference.self,
            forKey: AnyKey(stringValue: key)
        )

        if let core = Self.coreOperators.first(where: { core in core.key == key }) {
            self = .predicate(of: subject, operator: core.operator, operand: operand)

            return
        }

        guard let atom = library.atoms[key] else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "no predicate atom registered for '\(key)'"
                )
            )
        }

        // An atom's operand is validated at load when it is inert data — a
        // literal regex typo surfaces before any run, not inside one. An operand
        // that resolves at run time can only be judged there.
        if let constant = operand.constantValue {
            do {
                try atom.validate(constant)
            } catch {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: container.codingPath, debugDescription: "\(error)")
                )
            }
        }

        self = .predicate(of: subject, operator: .atom(key), operand: operand)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyKey.self)

        switch self {
        case .allOf(let conditions):
            try container.encode(conditions, forKey: AnyKey(stringValue: "all_of"))

        case .anyOf(let conditions):
            try container.encode(conditions, forKey: AnyKey(stringValue: "any_of"))

        case .not(let condition):
            try container.encode(condition, forKey: AnyKey(stringValue: "not"))

        case .predicate(let subject, let `operator`, let operand):
            let key: String

            switch `operator` {
            case .is:
                key = "is"

            case .isNot:
                key = "is_not"

            case .oneOf:
                key = "one_of"

            case .present:
                try container.encode(subject, forKey: AnyKey(stringValue: "present"))

                return

            case .atom(let name):
                key = name
            }

            try container.encode(subject, forKey: AnyKey(stringValue: Self.subjectKey))
            try container.encode(operand, forKey: AnyKey(stringValue: key))
        }
    }
}
