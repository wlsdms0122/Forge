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
    let name: String?

    // MARK: - Initializer
    init(path: String, reason: String, mtime: Date, name: String? = nil) {
        self.path = path
        self.reason = reason
        self.mtime = mtime
        self.name = name
    }

    // MARK: - Public
    // MARK: - Private
}
