//
//  ParallelFailed.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public struct ParallelFailed: RecoverableFailure {
    // MARK: - Property
    public let failures: [String: String]

    public var payload: Value {
        .object([
            "type": .string("parallel_failed"),
            "message": .string(message),
            "failures": .object(failures.mapValues(Value.string))
        ])
    }

    public var message: String {
        "parallel children failed: "
            + failures
                .sorted { left, right in left.key < right.key }
                .map { child, reason in "\(child): \(reason)" }
                .joined(separator: "; ")
    }

    // MARK: - Initializer
    public init(failures: [String: String]) {
        self.failures = failures
    }

    // MARK: - Public
    // MARK: - Private
}
