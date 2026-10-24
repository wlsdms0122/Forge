//
//  ResourceError.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// A resource that cannot be given: no resource directory, outside it, hidden, missing or unreadable.
struct ResourceError: ForgeError {
    // MARK: - Property
    let message: String

    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }

    // MARK: - Public
    // MARK: - Private
}
