//
//  BackendNotRegistered.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// No registered backend answers the provider an invocation names, or, when it
// names none, there is not exactly one backend to take.
struct BackendNotRegistered: ForgeError {
    // MARK: - Property
    let message: String

    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }

    // MARK: - Public
    // MARK: - Private
}
