//
//  HandlerFailed.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// A message a service's handler answered with an error; the message is the handler's.
struct HandlerFailed: ForgeError {
    // MARK: - Property
    let message: String

    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }

    // MARK: - Public
    // MARK: - Private
}
