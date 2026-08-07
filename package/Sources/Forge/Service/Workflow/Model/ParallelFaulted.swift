//
//  ParallelFaulted.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ParallelFaulted: ForgeError {
    // MARK: - Property
    let failures: [ParallelChildFailure]
    let message: String
    
    // MARK: - Initializer
    init(failures: [ParallelChildFailure]) {
        self.failures = failures
        self.message = ParallelFailed.describe(failures)
    }
    
    // MARK: - Public
    // MARK: - Private
}
