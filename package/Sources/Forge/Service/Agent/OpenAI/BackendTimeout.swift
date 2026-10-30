//
//  BackendTimeout.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct BackendTimeout: BackendError, WorkFailure {
    // MARK: - Property
    let message: String

    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }

    // MARK: - Public
    // MARK: - Private
}
