//
//  SocketError.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// The daemon's socket cannot be opened, bound or listened on.
struct SocketError: ForgeError {
    // MARK: - Property
    let message: String

    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }

    // MARK: - Public
    // MARK: - Private
}
