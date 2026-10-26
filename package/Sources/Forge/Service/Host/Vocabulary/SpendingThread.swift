//
//  SpendingThread.swift
//  Forge
//
//  Created by JSilver on 10/26/26.
//

import Foundation

// The thread a spend through the front end runs on, its caller waiting. A
// spend walks the text recursively and takes stack as deep as the text
// nests, past what a thread of the cooperative pool holds; the front end
// asks its host for a thread of 4 MiB or more.
struct SpendingThread: Sendable {
    // The work handed to the thread. The thread reads `result` first, which
    // runs the body there; the caller reads it once the thread signals.
    private final class Spend<Value: Sendable>: @unchecked Sendable {
        // MARK: - Property
        let finished = DispatchSemaphore(value: 0)

        lazy var result = Result { try body() }

        private let body: @Sendable () throws -> Value

        // MARK: - Initializer
        init(_ body: @escaping @Sendable () throws -> Value) {
            self.body = body
        }

        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    static let stackSize = 8 << 20

    // MARK: - Initializer
    // MARK: - Public
    func run<Value: Sendable>(_ body: @escaping @Sendable () throws -> Value) throws -> Value {
        let spend = Spend(body)
        let thread = Thread {
            _ = spend.result
            spend.finished.signal()
        }

        thread.stackSize = Self.stackSize
        thread.start()
        spend.finished.wait()

        return try spend.result.get()
    }

    // MARK: - Private
}
