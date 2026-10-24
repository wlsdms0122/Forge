//
//  AgentValidationError.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// An agent whose settings cannot be built: its model, tools or permission mode, or a combination its provider cannot run.
struct AgentValidationError: ForgeError {
    // MARK: - Property
    let message: String

    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }

    // MARK: - Public
    // MARK: - Private
}
