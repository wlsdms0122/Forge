//
//  ResourceLock.swift
//  ForgeTests
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// Per-name FIFO asynchronous lock.
actor ResourceLock {
    // MARK: - Property
    static let shared = ResourceLock()

    private var held: Set<String> = []
    private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]

    // MARK: - Initializer
    // MARK: - Public
    func acquire(_ name: String) async {
        if held.insert(name).inserted {
            return
        }

        await withCheckedContinuation { continuation in
            waiting[name, default: []].append(continuation)
        }
    }

    func release(_ name: String) {
        guard var queue = waiting[name], !queue.isEmpty else {
            held.remove(name)
            return
        }

        // Hand the lock straight to the next waiter without releasing it — leaves no gap to slip into
        let next = queue.removeFirst()
        waiting[name] = queue.isEmpty ? nil : queue
        next.resume()
    }

    // MARK: - Private
}
