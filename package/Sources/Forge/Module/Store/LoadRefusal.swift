//
//  LoadRefusal.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// A spec file's decode refusing it with a line of its own for the reload's
// announcement, where the store's `load failed` line would not say it.
struct LoadRefusal: ForgeError {
    // MARK: - Property
    let message: String
    let line: String
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
