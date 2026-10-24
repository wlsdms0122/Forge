//
//  AgentSessionMissing.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// An agent turn asked for outside an `invoke`, where no agent session is open.
struct AgentSessionMissing: ForgeError {
    // MARK: - Property
    let message: String

    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }

    // MARK: - Public
    // MARK: - Private
}
