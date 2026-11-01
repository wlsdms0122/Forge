//
//  InputValidationError.swift
//  Forge
//
//  Created by JSilver on 11/1/26.
//

import Foundation

// A run whose inputs do not fit what its `main` declares: a name it does not
// declare, nothing for a parameter that is not Optional, or a value of
// another type.
struct InputValidationError: ForgeError {
    // MARK: - Property
    let message: String

    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }

    // MARK: - Public
    // MARK: - Private
}
