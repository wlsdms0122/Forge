//
//  EachActionTests.swift
//  SpecTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Spec

@Suite
struct EachActionTests {
    // MARK: - Property
    private let loader = SpecLoader.testing

    // MARK: - Initializer
    // MARK: - Test
    @Test("each collects round results into an array")
    func eachMapsRounds() async throws {
        // Given
        let spec = try loader.load("""
        name: mapping
        inputs:
          items: array
        steps:
          - id: walk
            each:
              in: { ref: inputs.items }
              steps:
                - id: labeled
                  value:
                    format: "${index}:${item}"
                    with:
                      index: { ref: walk.index }
                      item: { ref: walk.item }
              output: { ref: labeled }
        outputs:
          result: { ref: walk }
          size: { ref: inputs.items.count }
        """)
        let sut = Executor()

        // When
        let outputs = try await sut.run(
            spec,
            inputs: ["items": .array([.string("a"), .string("b")])]
        )

        // Then
        #expect(outputs["result"] == .array([.string("0:a"), .string("1:b")]))
        #expect(outputs["size"] == .int(2))
    }

    @Test("walking non-array material is unfit")
    func nonArrayMaterialThrowsUnfit() async throws {
        // Given
        let spec = try loader.load("""
        name: unfit-each
        inputs:
          items: string
        steps:
          - id: walk
            each:
              in: { ref: inputs.items }
              steps:
                - id: noop
                  value: x
        """)
        let sut = Executor()

        // When / Then
        await #expect(throws: ReferenceUnfit.self) {
            try await sut.run(spec, inputs: ["items": .string("not-a-list")])
        }
    }

    @Test("with literal material the step id names the locus")
    func literalMaterialBlamesStepID() async throws {
        // Given — a literal `in` has no path to blame, so the step id carries it
        let spec = try loader.load("""
        name: literal-each
        steps:
          - id: walk
            each:
              in: not-a-list
              steps:
                - id: noop
                  value: x
        """)

        // When / Then
        do {
            _ = try await Executor().run(spec)
            Issue.record("expected ExecutionError")
        } catch let error as ExecutionError {
            #expect(error.message.contains("walk"), "\(error)")
        }
    }
}
