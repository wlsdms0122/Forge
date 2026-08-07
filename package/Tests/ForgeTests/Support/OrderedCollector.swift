//
//  OrderedCollector.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

/// Collects values in exactly the order the callback delivered them.
///
/// Handing off inside the callback with `Task { await actor.append(...) }` scatters each
/// element into **an independent task**, so arrival order is not preserved. For tests where
/// order is the premise of the assertion (does the line callback see stdout completely and
/// in sequence), that alone is flaky — observed in practice as reordered frames going red.
/// With a synchronous append, the order is already fixed by the time the callback returns.
final class OrderedCollector<Element: Sendable>: @unchecked Sendable {
    // MARK: - Property
    private let lock = NSLock()
    private var storage: [Element] = []

    // MARK: - Initializer
    // MARK: - Public
    var elements: [Element] {
        lock.withLock { storage }
    }

    func append(_ element: Element) {
        lock.withLock { storage.append(element) }
    }

    // MARK: - Private
}
