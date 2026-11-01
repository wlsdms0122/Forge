//
//  ConfigError.swift
//  Forge
//
//  Created by JSilver on 11/1/26.
//

import Foundation

// A config the loader cannot take as written: a named file that is not there,
// a key it does not read, or a value of another type than its key takes.
struct ConfigError: ForgeError {
    // MARK: - Property
    let message: String
    
    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }
    
    // MARK: - Public
    // MARK: - Private
}
