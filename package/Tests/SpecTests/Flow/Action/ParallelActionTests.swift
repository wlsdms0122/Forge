//
//  ParallelActionTests.swift
//  SpecTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Spec

@Suite
struct ParallelActionTests {
    // MARK: - Property
    private let loader = SpecLoader.testing

    // MARK: - Initializer
    // MARK: - Test
    @Test("sibling results collect into one object keyed by child id")
    func parallelCollectsChildrenByID() async throws {
        // Given
        let spec = try loader.load("""
        name: fanning
        inputs:
          who: string
        steps:
          - id: par
            parallel:
              - id: left
                value: { format: "hi, ${who}", with: { who: { ref: inputs.who } } }
              - id: right
                value: 42
          - id: after
            value:
              format: "${left} / ${right}"
              with:
                left: { ref: par.left }
                right: { ref: par.right }
        outputs:
          result: { ref: after }
        """)
        let sut = Executor()

        // When
        let outputs = try await sut.run(spec, inputs: ["who": .string("spec")])

        // Then — siblings collect into one object keyed by child id
        #expect(outputs["result"] == .string("hi, spec / 42"))
    }

    @Test("the host's isolation boundary wraps every child")
    func environmentIsolatesEachChild() async throws {
        // Given
        let spec = try loader.load("""
        name: bounded
        steps:
          - id: par
            parallel:
              - id: left
                value: 1
              - id: right
                value: 2
        outputs:
          result: { ref: par }
        """)
        let boundary = IsolationBoundaryProbe()
        let sut = Executor(environment: boundary)

        // When
        let outputs = try await sut.run(spec)

        // Then — every child body walked through the host's isolation boundary
        #expect(boundary.isolatedCount == 2)
        #expect(outputs["result"] == .object(["left": .int(1), "right": .int(2)]))
    }

    @Test("all-recoverable failures rescue")
    func allRecoverableFailuresRescue() async throws {
        // Given
        let spec = try loader.load("""
        name: fan-fail
        steps:
          - id: par
            parallel:
              - id: fine
                value: ok
              - id: fragile
                fail: true
            rescue:
              - id: recovery
                value: recovered
        outputs:
          result: { ref: par }
        """)
        let sut = Executor()

        // When
        let outputs = try await sut.run(spec)

        // Then
        #expect(outputs["result"] == .string("recovered"))
    }

    @Test("one child's author mistake propagates the composite")
    func anyFatalChildPropagates() async throws {
        // Given — one author mistake makes the composite an author mistake
        let spec = try loader.load("""
        name: fan-fault
        steps:
          - id: par
            parallel:
              - id: fragile
                fail: true
              - id: broken
                fail: false
            rescue:
              - id: recovery
                value: recovered
        """)
        let sut = Executor()

        // When / Then
        await #expect(throws: TestFatalError.self) {
            try await sut.run(spec)
        }
    }

    @Test("the designated initializer also rejects duplicate ids and empty lists")
    func duplicateChildIDsRejectedAtInit() {
        // Given / When / Then — the invariant holds on the designated
        // initializer, not only on the decoder
        #expect(throws: ValidationError.self) {
            try ParallelAction(steps: [
                Step(id: "twin", action: ValueAction(reference: .stringValue("a"))),
                Step(id: "twin", action: ValueAction(reference: .stringValue("b")))
            ])
        }
        #expect(throws: ValidationError.self) {
            try ParallelAction(steps: [])
        }
    }
}

// Probe environment counting how many children pass through the isolation hook.
private final class IsolationBoundaryProbe: ParallelIsolating, @unchecked Sendable {
    // MARK: - Property
    private let lock = NSLock()
    private var count = 0

    var isolatedCount: Int {
        lock.withLock { count }
    }

    // MARK: - Initializer
    // MARK: - Public
    func isolateParallelChild<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        lock.withLock { count += 1 }

        return try await body()
    }

    // MARK: - Private
}
