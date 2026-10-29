//
//  BackendProtocolViolation.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct BackendProtocolViolation: ForgeError {
    // MARK: - Property
    let message: String

    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }

    // MARK: - Public
    // MARK: - Private
}
