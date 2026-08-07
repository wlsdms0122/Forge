//
//  Derivation.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// A named value transformation reachable as a path segment — `.count`, whatever
// a host adds. Returning nil means the word does not apply to that value shape.
public struct Derivation: Sendable {
    // MARK: - Property
    public let key: String
    public let derive: @Sendable (Value) -> Value?

    // MARK: - Initializer
    public init(key: String, derive: @escaping @Sendable (Value) -> Value?) {
        self.key = key
        self.derive = derive
    }

    // MARK: - Public
    // MARK: - Private
}
