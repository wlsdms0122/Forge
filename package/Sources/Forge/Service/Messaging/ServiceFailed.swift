//
//  ServiceFailed.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// A message a service answered with an error; the message is the service's.
struct ServiceFailed: ForgeError {
    // MARK: - Property
    let message: String

    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }

    // MARK: - Public
    // MARK: - Private
}
