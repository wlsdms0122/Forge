//
//  DeadlineExceeded.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

struct DeadlineExceeded: Warp.RecoverableFailure {
    // MARK: - Property
    static let type = "timeout"

    let message: String
    let seconds: Double

    var type: String { Self.type }

    var details: Value.Dictionary { Value.Dictionary(["seconds": .double(seconds)]) }

    // MARK: - Initializer
    init(seconds: Double) {
        self.message = "step timed out after \(seconds)s"
        self.seconds = seconds
    }

    // MARK: - Public
    // MARK: - Private
}
