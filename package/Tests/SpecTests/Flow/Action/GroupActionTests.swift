//
//  GroupActionTests.swift
//  SpecTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Spec

@Suite
struct GroupActionTests {
    // MARK: - Property
    private let loader = SpecLoader.testing

    // MARK: - Initializer
    // MARK: - Test
    @Test("inner bindings stay inside; the group speaks with its declared output")
    func groupSpeaksWithDeclaredOutput() async throws {
        // Given
        let spec = try loader.load("""
        name: grouped
        inputs:
          who: string
        steps:
          - id: greet
            group:
              steps:
                - id: base
                  value: { format: "hello, ${who}", with: { who: { ref: inputs.who } } }
                - id: loud
                  value: { format: "${text}!", with: { text: { ref: base } } }
              output: { ref: loud }
        outputs:
          result: { ref: greet }
        """)
        let sut = Executor()

        // When
        let outputs = try await sut.run(spec, inputs: ["who": .string("spec")])

        // Then — inner bindings stay inside; the group speaks with one output
        #expect(outputs["result"] == .string("hello, spec!"))
    }

    @Test("without a declared output the last step speaks")
    func groupSpeaksLastOutputByDefault() async throws {
        // Given — a sequence speaks with its last statement, the same rule
        // rescue follows
        let spec = try loader.load("""
        name: implicit-group
        steps:
          - id: block
            group:
              steps:
                - id: first
                  value: a
                - id: second
                  value: b
        outputs:
          result: { ref: block }
        """)
        let sut = Executor()

        // When
        let outputs = try await sut.run(spec)

        // Then
        #expect(outputs["result"] == .string("b"))
    }

    @Test("a group body reading its own id is rejected at load")
    func groupSelfReadRejected() {
        // Given — group binds nothing for its body; `${g.x}` inside it is a typo
        let yaml = """
        name: self-read
        steps:
          - id: g
            group:
              steps:
                - id: inner
                  value: { ref: g.x }
        """

        // When / Then
        #expect(throws: ValidationError.self) {
            try loader.load(yaml)
        }
    }
}
