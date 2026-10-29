//
//  OutputDeclarationError.swift
//  Forge
//
//  Created by JSilver on 10/24/26.
//

import Foundation

struct OutputDeclarationError: ForgeError {
    // MARK: - Property
    let message: String
    
    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }
    
    // MARK: - Public
    // MARK: - Private
}
