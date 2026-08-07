//
//  LoadGateTests.swift
//  SpecTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Spec

@Suite
struct LoadGateTests {
    // MARK: - Property
    private let loader = SpecLoader.testing

    // MARK: - Initializer
    // MARK: - Test
    @Test("an unknown step key is rejected at load")
    func unknownStepKeyRejected() {
        // Given
        let yaml = """
        name: typo
        steps:
          - id: broken
            value: x
            fallbck: y
        """

        // When / Then
        #expect(throws: DecodingError.self) {
            try loader.load(yaml)
        }
    }

    @Test("a step declaring two actions is rejected")
    func doubleActionStepRejected() {
        // Given
        let yaml = """
        name: double
        steps:
          - id: broken
            value: x
            fail: true
        """

        // When / Then
        #expect(throws: DecodingError.self) {
            try loader.load(yaml)
        }
    }

    @Test("an unknown reference head is caught at load, not at run")
    func unknownReferenceHeadRejected() {
        // Given — forward references and typos surface at load, not at run
        let yaml = """
        name: forward
        steps:
          - id: early
            value: { ref: later }
          - id: later
            value: x
        """

        // When / Then
        #expect(throws: ValidationError.self) {
            try loader.load(yaml)
        }
    }

    @Test("duplicate sibling step ids are rejected")
    func duplicateSiblingIDsRejected() {
        // Given
        let yaml = """
        name: duplicated
        steps:
          - id: twin
            value: x
          - id: twin
            value: y
        """

        // When / Then
        #expect(throws: ValidationError.self) {
            try loader.load(yaml)
        }
    }

    @Test("a step id colliding with a reserved head is rejected")
    func reservedHeadCollisionRejected() {
        // Given
        let yaml = """
        name: reserved
        steps:
          - id: inputs
            value: x
        """

        // When / Then
        #expect(throws: ValidationError.self) {
            try loader.load(yaml)
        }
    }

    @Test("an empty rescue is rejected")
    func emptyRescueRejected() {
        // Given
        let yaml = """
        name: hollow
        steps:
          - id: fragile
            fail: true
            rescue: []
        """

        // When / Then
        #expect(throws: ValidationError.self) {
            try loader.load(yaml)
        }
    }

    @Test("a typo in a nested index reference is caught at load")
    func indexReferenceTypoRejected() {
        // Given
        let yaml = """
        name: index-typo
        inputs:
          items: array
        steps:
          - id: pick
            value: { ref: "inputs.items[${typoooo}]" }
        """

        // When / Then — nested index refs are part of the reference, not a blind spot
        #expect(throws: ValidationError.self) {
            try loader.load(yaml)
        }
    }

    @Test("an empty index segment is rejected at parse")
    func emptyIndexSegmentRejected() {
        // Given — `[]` is an author mistake, rejected at parse instead of being
        // carried into the model
        let yaml = """
        name: empty-index
        inputs:
          items: array
        steps:
          - id: pick
            value: { ref: "inputs.items[]" }
        """

        // When / Then
        #expect(throws: DecodingError.self) {
            try loader.load(yaml)
        }
    }

    @Test("a context head loads only where the loader declares it")
    func declaredContextHeadLoads() throws {
        // Given
        let contextual = SpecLoader(
            registry: loader.registry,
            contextHeads: ["run"]
        )
        let yaml = """
        name: contextual
        steps:
          - id: whoami
            value: { ref: run.id }
        """

        // When / Then
        #expect(throws: Never.self) {
            try contextual.load(yaml)
        }
        #expect(throws: ValidationError.self) {
            try loader.load(yaml)
        }
    }

    @Test("runtime data becomes IR through the loader's Value door")
    func valueLowersThroughFrontendDoor() throws {
        // Given — a step array that arrived as data (through a signature) becomes
        // IR via the loader's Value door; the string stays a literal even there
        let carried = Value.array([
            .object(["id": .string("greet"), "value": .string("hello there")])
        ])

        // When
        let steps = try loader.decode([Step].self, from: carried)

        // Then
        #expect(steps.count == 1)
        #expect(steps[0].id == "greet")
        #expect(steps[0].actionKey == "value")
    }

    @Test("a spec survives the encoding round trip")
    func specRoundTripsThroughEncoder() throws {
        // Given
        let yaml = """
        name: round-trip
        inputs:
          who:
            type: string
            default: world
        steps:
          - id: gate
            when:
              present: { ref: inputs.who }
            value: { format: "hello, ${who}", with: { who: { ref: inputs.who } } }
            rescue:
              - id: recovery
                value: fallback
        outputs:
          result: { ref: gate }
        """
        let spec = try loader.load(yaml)

        // When
        let encoder = JSONEncoder()
        encoder.userInfo[.actionRegistry] = SpecLoader.testing.registry

        let data = try encoder.encode(spec)
        let decoder = JSONDecoder()
        decoder.userInfo[.actionRegistry] = SpecLoader.testing.registry

        let reloaded = try decoder.decode(Program.self, from: data)

        // Then
        #expect(reloaded.name == spec.name)
        #expect(reloaded.steps.count == spec.steps.count)
        #expect(reloaded.steps[0].actionKey == "value")
        #expect(reloaded.steps[0].rescue?.count == 1)
    }
}
