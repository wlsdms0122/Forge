//
//  ExclusiveResource.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing

/// Keeps tests that touch process-global resources from overlapping.
///
/// swift-testing runs in parallel by default, and `.serialized` only serializes *within* a
/// suite. When several suites touch the same global (`Log.shared` has four suites swapping
/// its sink), that is not enough. This trait shares a lock among tests declaring the same
/// name, serializing them **across files**.
///
///     @Suite(.exclusive(.logSink))
///     struct LogTests { ... }
///
/// Different resource names do not block each other, so parallelism is lost only as much as needed.
struct ExclusiveResource: TestTrait, SuiteTrait, TestScoping {
    // MARK: - Property
    let name: String

    var isRecursive: Bool { true }

    // MARK: - Public
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        // Wrap only the individual test execution, not the suite itself
        guard testCase != nil else {
            try await function()
            return
        }

        await ResourceLock.shared.acquire(name)
        do {
            try await function()
        } catch {
            await ResourceLock.shared.release(name)
            throw error
        }

        await ResourceLock.shared.release(name)
    }
}

extension Trait where Self == ExclusiveResource {
    static func exclusive(_ resource: ExclusiveResource.Name) -> Self {
        ExclusiveResource(name: resource.rawValue)
    }
}

extension ExclusiveResource {
    /// Passing names as loose strings lets a typo silently become a 'different resource' — pin them with an enum.
    enum Name: String {
        /// `Log.shared` — process-global sink. Every test that calls `setSink`.
        case logSink
        /// `StubURLProtocol.handler` / `.failure` — static mutable stubs.
        case stubURLProtocol
        /// `STDERR_FILENO` — process-global fd. Every test that swaps out standard error.
        case standardError
    }
}

/// Per-name FIFO asynchronous lock.
private actor ResourceLock {
    // MARK: - Property
    static let shared = ResourceLock()

    private var held: Set<String> = []
    private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]

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
}
