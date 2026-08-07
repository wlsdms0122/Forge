//
//  SpawnGuard.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

final class SpawnGuard: @unchecked Sendable {
    // MARK: - Property
    private let lock = NSLock()
    private var cancelled = false
    private var started = false

    // MARK: - Initializer
    // MARK: - Public
    func markStarted() -> Bool {
        lock.lock()

        defer { lock.unlock() }

        started = true

        return cancelled
    }

    func markCancelled() -> Bool {
        lock.lock()

        defer { lock.unlock() }

        cancelled = true

        return started
    }

    // MARK: - Private
}
