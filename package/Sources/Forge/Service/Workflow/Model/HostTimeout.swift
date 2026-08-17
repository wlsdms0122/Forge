//
//  HostTimeout.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

struct HostTimeout: Warp.RecoverableFailure {
    // MARK: - Property
    let message: String
    let seconds: Double

    var payload: Warp.Value {
        .object([
            "type": .string("timeout"),
            "message": .string(message),
            "seconds": .double(seconds)
        ])
    }

    // MARK: - Initializer
    init(seconds: Double) {
        self.message = "step timed out after \(seconds)s"
        self.seconds = seconds
    }

    // MARK: - Public
    // MARK: - Private
}
