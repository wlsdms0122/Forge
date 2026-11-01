//
//  CatalogIncomplete.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// The catalog directory was not fully read, so the catalog cannot answer for
// a workflow name.
struct CatalogIncomplete: ForgeError {
    // MARK: - Property
    let message: String

    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }

    // MARK: - Public
    // MARK: - Private
}
