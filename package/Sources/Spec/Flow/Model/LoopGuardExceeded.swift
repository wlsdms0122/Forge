//
//  LoopGuardExceeded.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public struct LoopGuardExceeded: RecoverableFailure {
    // MARK: - Property
    public let stepID: String
    public let limit: Int

    public var message: String {
        "loop '\(stepID)' where-condition still true after \(limit) iterations"
    }

    public var payload: Value {
        .object([
            "type": .string("loop_guard_exceeded"),
            "message": .string(message),
            "limit": .int(limit)
        ])
    }

    // MARK: - Initializer
    public init(stepID: String, limit: Int) {
        self.stepID = stepID
        self.limit = limit
    }

    // MARK: - Public
    // MARK: - Private
}
