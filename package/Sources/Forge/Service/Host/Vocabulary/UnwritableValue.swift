//
//  UnwritableValue.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// A value JSON cannot hold, met where it leaves for the wire.
struct UnwritableValue: ForgeError {
    // MARK: - Property
    let message: String

    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }

    // MARK: - Public
    // MARK: - Private
}
