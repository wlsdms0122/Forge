//
//  LoadFailure.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct LoadFailure: Sendable, Equatable {
    // MARK: - Property
    let path: String
    let reason: String
    let mtime: Date

    // MARK: - Initializer
    init(path: String, reason: String, mtime: Date) {
        self.path = path
        self.reason = reason
        self.mtime = mtime
    }

    // MARK: - Public
    // MARK: - Private
}
