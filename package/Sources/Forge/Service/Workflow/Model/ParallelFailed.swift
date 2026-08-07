//
//  ParallelFailed.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ParallelFailed: WorkFailure {
    // MARK: - Property
    let failures: [ParallelChildFailure]
    let message: String
    
    // MARK: - Initializer
    init(failures: [ParallelChildFailure]) {
        self.failures = failures
        self.message = Self.describe(failures)
    }
    
    // MARK: - Public
    static func describe(_ failures: [ParallelChildFailure]) -> String {
        "parallel: \(failures.count) child step(s) failed — "
            + failures
                .map { failure in "\(failure.id): \(failure.type) — \(failure.message)" }
                .joined(separator: " | ")
    }
    
    // MARK: - Private
}
