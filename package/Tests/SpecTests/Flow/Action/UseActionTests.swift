//
//  UseActionTests.swift
//  SpecTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Spec

@Suite
struct UseActionTests {
    // MARK: - Property
    private let loader = SpecLoader.testing

    // MARK: - Initializer
    // MARK: - Test
    @Test("the callee signature settles inputs at the call boundary")
    func calleeSignatureSettlesInputs() async throws {
        // Given
        let callee = try loader.load("""
        name: callee
        inputs:
          base: int
          bump:
            type: int
            default: 1
        steps:
          - id: echo
            value:
              base: { ref: inputs.base }
              bump: { ref: inputs.bump }
        outputs:
          pair: { ref: echo }
        """)
        let caller = try loader.load("""
        name: caller
        steps:
          - id: call
            use:
              spec: callee
              inputs:
                base: 41
        outputs:
          result: { ref: call.pair }
        """)
        let sut = Executor(store: MemoryStore(specs: ["callee": callee]))

        // When
        let outputs = try await sut.run(caller)

        // Then — the omitted `bump` settled to its default at the callee boundary
        #expect(outputs["result"] == .object(["base": .int(41), "bump": .int(1)]))
    }

    @Test("a call violating the callee signature is rejected")
    func signatureViolationRejectsCall() async throws {
        // Given
        let callee = try loader.load("""
        name: callee
        inputs:
          base: int
        steps:
          - id: echo
            value: { ref: inputs.base }
        """)
        let caller = try loader.load("""
        name: caller
        steps:
          - id: call
            use:
              spec: callee
              inputs:
                base: not-a-number
        """)
        let sut = Executor(store: MemoryStore(specs: ["callee": callee]))

        // When / Then
        await #expect(throws: InputValidationError.self) {
            try await sut.run(caller)
        }
    }

    @Test("runaway recursive calls end by host cancellation")
    func recursiveCallStopsOnCancellation() async throws {
        // Given — the kernel carries no recursion guard (a reappearing name is not
        // a cycle oracle); runaway calls end by host cancellation, which must
        // propagate through the call chain
        let loopy = try loader.load("""
        name: loopy
        steps:
          - id: again
            use:
              spec: loopy
        """)
        let sut = Executor(store: MemoryStore(specs: ["loopy": loopy]))

        // When
        let task = Task {
            try await sut.run(loopy)
        }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        // Then
        await #expect(throws: (any Error).self) {
            try await task.value
        }
    }
}
