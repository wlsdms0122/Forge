//
//  PredicateAtom.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// A named question a predicate can ask of a resolved value — `contains`,
// `starts_with`, whatever a host adds. `resolved` is nil when the path was
// absent; atoms answer false for absence and throw ReferenceUnfit for shape
// misuse, matching the kernel's absence/unfit split. `validate` gates the
// literal operand at load, so an author typo surfaces before any run.
public struct PredicateAtom: Sendable {
    // MARK: - Property
    public let key: String
    public let validate: @Sendable (Value) throws -> Void
    public let evaluate: @Sendable (Value?, Value, [PathSegment]) throws -> Bool

    // MARK: - Initializer
    public init(
        key: String,
        validate: @escaping @Sendable (Value) throws -> Void = { _ in },
        evaluate: @escaping @Sendable (Value?, Value, [PathSegment]) throws -> Bool
    ) {
        self.key = key
        self.validate = validate
        self.evaluate = evaluate
    }

    // MARK: - Public
    // MARK: - Private
}
