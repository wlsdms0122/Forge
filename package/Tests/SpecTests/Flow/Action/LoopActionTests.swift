//
//  LoopActionTests.swift
//  SpecTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Spec

@Suite
struct LoopActionTests {
    // MARK: - Property
    private let loader = SpecLoader.testing

    // MARK: - Initializer
    // MARK: - Test
    @Test("loop repeats while its where holds")
    func loopRepeatsWhileConditionHolds() async throws {
        // Given — the loop rebinds `latest` each round (shadowing idiom) and reads
        // its own round index through ${gate.index}
        let spec = try loader.load("""
        name: looping
        steps:
          - id: latest
            value: 0
          - id: gate
            loop:
              where:
                { of: { ref: "gate.index" }, is_not: 3 }
              steps:
                - id: latest
                  value: { ref: gate.index }
              guard: 5
              output: { ref: latest }
        outputs:
          result: { ref: gate }
        """)
        let sut = Executor()

        // When
        let outputs = try await sut.run(spec)

        // Then — rounds 0/1/2 ran; at index 3 the where turned false
        #expect(outputs["result"] == .int(2))
    }

    @Test("a guardless loop runs unbounded, like while")
    func loopRunsUnboundedWithoutGuard() async throws {
        // Given — like `while`, the language does not demand a budget; the world
        // (here, the condition) ends the repetition
        let spec = try loader.load("""
        name: unbounded
        steps:
          - id: latest
            value: 0
          - id: gate
            loop:
              where:
                { of: { ref: "gate.index" }, is_not: 7 }
              steps:
                - id: latest
                  value: { ref: gate.index }
              output: { ref: latest }
        outputs:
          result: { ref: gate }
        """)
        let sut = Executor()

        // When
        let outputs = try await sut.run(spec)

        // Then
        #expect(outputs["result"] == .int(6))
    }

    @Test("an exhausted guard is an error")
    func exhaustedGuardThrows() async throws {
        // Given
        let spec = try loader.load("""
        name: runaway
        steps:
          - id: gate
            loop:
              where:
                present: { ref: inputs }
              steps:
                - id: noop
                  value: again
              guard: 2
        """)
        let sut = Executor()

        // When / Then
        await #expect(throws: LoopGuardExceeded.self) {
            try await sut.run(spec)
        }
    }

    @Test("an empty-body loop still observes cancellation")
    func emptyBodyObservesCancellation() async throws {
        // Given — an empty body must still observe cancellation, or the host's
        // one lever against a runaway loop stops working
        let spec = try loader.load("""
        name: hollow-loop
        steps:
          - id: gate
            loop:
              where:
                present: { ref: "gate.index" }
              steps: []
        """)
        let sut = Executor()

        // When
        let task = Task {
            try await sut.run(spec)
        }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        // Then
        await #expect(throws: (any Error).self) {
            try await task.value
        }
    }

    @Test("a loop body may rebind an outer id by shadowing")
    func loopRebindsOuterIDByShadowing() throws {
        // Given — the retry-loop idiom rebinds an outer id inside loop steps
        let yaml = """
        name: shadowing
        steps:
          - id: format
            value: first
          - id: gate
            loop:
              where:
                { of: { ref: "gate.index" }, is: 0 }
              steps:
                - id: format
                  value: retried
              guard: 2
        """

        // When / Then
        #expect(throws: Never.self) {
            try loader.load(yaml)
        }
    }
}
