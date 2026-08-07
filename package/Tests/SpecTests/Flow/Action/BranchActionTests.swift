//
//  BranchActionTests.swift
//  SpecTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Spec

@Suite
struct BranchActionTests {
    // MARK: - Property
    private let loader = SpecLoader.testing

    // MARK: - Initializer
    // MARK: - Test
    @Test("branch selects the then/else arm by its condition")
    func branchSelectsArm() async throws {
        // Given
        let spec = try loader.load("""
        name: branching
        inputs:
          kind: string
        steps:
          - id: pick
            branch:
              when:
                { of: { ref: inputs.kind }, is: a }
              then:
                steps:
                  - id: chosen
                    value: took-then
                output: { ref: chosen }
              else:
                steps:
                  - id: chosen
                    value: took-else
                output: { ref: chosen }
        outputs:
          result: { ref: pick }
        """)
        let sut = Executor()

        // When
        let thenOutputs = try await sut.run(spec, inputs: ["kind": .string("a")])
        let elseOutputs = try await sut.run(spec, inputs: ["kind": .string("b")])

        // Then
        #expect(thenOutputs["result"] == .string("took-then"))
        #expect(elseOutputs["result"] == .string("took-else"))
    }
}
