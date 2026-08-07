//
//  SignatureTests.swift
//  SpecTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Spec

@Suite
struct SignatureTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("an omitted input fills from its default")
    func omittedInputFillsDefault() throws {
        // Given
        let sut = Signature(parameters: [
            "mode": Parameter(type: .string, default: .string("fast"))
        ])

        // When
        let settled = try sut.settle([:])

        // Then
        #expect(settled["mode"] == .string("fast"))
    }

    @Test("a missing required input is rejected")
    func missingRequiredInputRejected() {
        // Given
        let sut = Signature(parameters: ["name": Parameter(type: .string)])

        // When / Then
        #expect(throws: InputValidationError.self) {
            try sut.settle([:])
        }
    }

    @Test("a type mismatch is rejected")
    func typeMismatchRejected() {
        // Given
        let sut = Signature(parameters: ["count": Parameter(type: .int)])

        // When / Then
        #expect(throws: InputValidationError.self) {
            try sut.settle(["count": .string("three")])
        }
    }

    @Test("a whole double settles narrowed to int")
    func wholeDoubleNarrowsToInt() throws {
        // Given
        let sut = Signature(parameters: ["count": Parameter(type: .int)])

        // When
        let settled = try sut.settle(["count": .double(3.0)])

        // Then — settling normalizes to the declared representation
        #expect(settled["count"] == .int(3))
    }

    @Test("an undeclared input name is rejected")
    func undeclaredInputRejected() {
        // Given
        let sut = Signature(parameters: ["a": Parameter(type: .string)])

        // When / Then — an extra name is a typo surfaced, not a value smuggled in
        #expect(throws: InputValidationError.self) {
            try sut.settle(["a": .string("x"), "sneaky": .int(9)])
        }
    }

    @Test("a value outside oneOf is rejected")
    func valueOutsideOneOfRejected() {
        // Given
        let sut = Signature(parameters: [
            "mode": Parameter(type: .string, oneOf: ["fast", "slow"])
        ])

        // When / Then
        #expect(throws: InputValidationError.self) {
            try sut.settle(["mode": .string("medium")])
        }
    }

    @Test("a default failing its own gate is rejected at declaration")
    func defaultFailingOwnGateRejected() {
        // Given
        let sut = SpecLoader.testing
        let yaml = """
        name: bad-default
        inputs:
          mode:
            type: string
            oneOf: [fast, slow]
            default: medium
        steps:
          - id: noop
            value: ok
        """

        // When / Then
        #expect(throws: DecodingError.self) {
            try sut.load(yaml)
        }
    }

    @Test("a default is stored settled at declaration time")
    func suppliedDefaultSettlesAtLoad() throws {
        // Given — the stored default is the settled value, so a default-supplied
        // slot reads the same type a caller-supplied one would
        let spec = try SpecLoader.testing.load("""
        name: defaulted
        inputs:
          ratio:
            type: double
            default: 3
        steps:
          - id: echo
            value: { ref: inputs.ratio }
        outputs:
          result: { ref: echo }
        """)

        // When / Then
        #expect(spec.inputs.parameters["ratio"]?.default == .double(3.0))
    }

    @Test("no inputs declaration is still a closed contract — strays are rejected")
    func strayInputRejectedOnEmptySignature() async throws {
        // Given — absent `inputs:` is an empty signature, not an absent contract
        let spec = try SpecLoader.testing.load("""
        name: closed
        steps:
          - id: noop
            value: ok
        """)
        let sut = Executor()

        // When / Then
        await #expect(throws: InputValidationError.self) {
            try await sut.run(spec, inputs: ["stray": .string("leaked")])
        }
    }
}
