//
//  ProviderDeclarationError.swift
//  Forge
//
//  Created by JSilver on 10/30/26.
//

import Foundation

struct ProviderDeclarationError: ForgeError {
    // MARK: - Property
    let message: String
    
    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }
    
    // MARK: - Public
    // MARK: - Private
}
