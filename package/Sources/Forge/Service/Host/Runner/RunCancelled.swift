//
//  RunCancelled.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// A run stopped by `workflow.cancel` or by the daemon's shutdown.
struct RunCancelled: ForgeError {
    // MARK: - Property
    let message: String

    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }

    // MARK: - Public
    // MARK: - Private
}
