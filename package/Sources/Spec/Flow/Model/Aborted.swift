//
//  Aborted.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public struct Aborted: RecoverableFailure {
    // MARK: - Property
    public let message: String

    public var payload: Value {
        .object(["type": .string("aborted"), "message": .string(message)])
    }

    // MARK: - Initializer
    public init(_ message: String) {
        self.message = message
    }

    // MARK: - Public
    // MARK: - Private
}
