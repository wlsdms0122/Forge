//
//  ConditionTests.swift
//  SpecTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Spec

@Suite
struct ConditionTests {
    // MARK: - Property
    private let scope = Scope(inputs: ["kind": .string("a"), "n": .int(3), "none": .null])

    // MARK: - Initializer
    // MARK: - Test
    @Test("predicates evaluate against scope values")
    func predicatesEvaluateAgainstScope() throws {
        // Given
        let sut = Resolver(scope: scope)

        // Then
        #expect(try sut.evaluate(
            .predicate(of: .ref(path("inputs.kind")), operator: .is, operand: .stringValue("a"))
        ))
        #expect(try sut.evaluate(
            .predicate(of: .ref(path("inputs.kind")), operator: .isNot, operand: .stringValue("b"))
        ))
        #expect(try sut.evaluate(
            .predicate(
                of: .ref(path("inputs.n")),
                operator: .oneOf,
                operand: .arrayValue([.integerValue(3), .integerValue(4)])
            )
        ))
        #expect(try sut.evaluate(
            .predicate(of: .ref(path("inputs.n")), operator: .present, operand: nil)
        ))
        #expect(try !sut.evaluate(
            .predicate(of: .ref(path("inputs.none")), operator: .present, operand: nil)
        ))
        #expect(try !sut.evaluate(
            .predicate(of: .ref(path("inputs.gone")), operator: .present, operand: nil)
        ))
    }

    @Test("both sides of a predicate are expressions")
    func bothSidesAreExpressions() throws {
        // Given
        let sut = Resolver(scope: Scope(inputs: [
            "left": .string("same"),
            "right": .string("same"),
            "candidates": .array([.string("same"), .string("other")])
        ]))

        // Then — a reference compares against another reference
        #expect(try sut.evaluate(
            .predicate(
                of: .ref(path("inputs.left")),
                operator: .is,
                operand: .ref(path("inputs.right"))
            )
        ))

        // And one_of can draw its candidates from the scope
        #expect(try sut.evaluate(
            .predicate(
                of: .ref(path("inputs.left")),
                operator: .oneOf,
                operand: .ref(path("inputs.candidates"))
            )
        ))
    }

    @Test("numeric equality crosses int and double")
    func numericEqualityCrossesIntAndDouble() throws {
        // Given
        let sut = Resolver(scope: scope)

        // Then
        #expect(try sut.evaluate(
            .predicate(of: .ref(path("inputs.n")), operator: .is, operand: .doubleValue(3.0))
        ))
    }

    @Test("combinators compose nested conditions")
    func combinatorsCompose() throws {
        // Given
        let sut = Resolver(scope: scope)
        let condition = Condition.allOf([
            .predicate(of: .ref(path("inputs.kind")), operator: .is, operand: .stringValue("a")),
            .not(.predicate(of: .ref(path("inputs.n")), operator: .is, operand: .integerValue(4)))
        ])

        // Then
        #expect(try sut.evaluate(condition))
    }

    @Test("text atoms evaluate on strings; asking a number is unfit")
    func textAtomsEvaluateOnStrings() throws {
        // Given
        let sut = Resolver(scope: Scope(inputs: [
            "title": .string("hello, spec"),
            "tags": .array([.string("a"), .string("b")]),
            "n": .int(3)
        ]))

        // Then
        #expect(try sut.evaluate(
            .predicate(of: .ref(path("inputs.title")), operator: .atom("contains"), operand: .stringValue("spec"))
        ))
        #expect(try sut.evaluate(
            .predicate(of: .ref(path("inputs.tags")), operator: .atom("contains"), operand: .stringValue("b"))
        ))
        #expect(try sut.evaluate(
            .predicate(of: .ref(path("inputs.title")), operator: .atom("starts_with"), operand: .stringValue("hello"))
        ))
        #expect(try sut.evaluate(
            .predicate(of: .ref(path("inputs.title")), operator: .atom("regex"), operand: .stringValue("sp.c$"))
        ))
        #expect(try !sut.evaluate(
            .predicate(of: .ref(path("inputs.gone")), operator: .atom("contains"), operand: .stringValue("x"))
        ))

        // A text atom asking a number is shape misuse, not a false answer
        #expect(throws: ReferenceUnfit.self) {
            try sut.evaluate(
                .predicate(of: .ref(path("inputs.n")), operator: .atom("starts_with"), operand: .stringValue("3"))
            )
        }
    }

    @Test("an invalid regex pattern is rejected at load")
    func invalidRegexRejectedAtLoad() {
        // Given
        let yaml = """
        name: bad-pattern
        inputs:
          title: string
        steps:
          - id: gated
            when:
              { of: { ref: inputs.title }, regex: "[unclosed" }
            value: x
        """

        // When / Then — the pattern compiles at load, not inside a run
        #expect(throws: DecodingError.self) {
            try SpecLoader.testing.load(yaml)
        }
    }

    @Test("shape misuse in a condition is unfit, not false")
    func conditionShapeMisuseThrowsUnfit() {
        // Given
        let sut = Resolver(scope: scope)

        // When / Then — a typo'd drill must not silently read as false
        #expect(throws: ReferenceUnfit.self) {
            try sut.evaluate(
                .predicate(of: .ref(path("inputs.n.field")), operator: .present, operand: nil)
            )
        }
    }

    @Test("two operator keys in one condition are rejected")
    func doubleOperatorKeysRejected() {
        // Given
        let yaml = """
        name: double-operator
        inputs:
          k: string
        steps:
          - id: gated
            when:
              of: { ref: inputs.k }
              is: a
              is_not: b
            value: x
        """

        // When / Then — first-wins would silently drop the second predicate
        #expect(throws: DecodingError.self) {
            try SpecLoader.testing.load(yaml)
        }
    }

    @Test("a binary operator without a subject is rejected")
    func binaryOperatorWithoutSubjectRejected() {
        // Given
        let yaml = """
        name: no-subject
        inputs:
          k: string
        steps:
          - id: gated
            when:
              is: a
            value: x
        """

        // When / Then — is compares two sides; a lone operand names neither
        #expect(throws: DecodingError.self) {
            try SpecLoader.testing.load(yaml)
        }
    }

    @Test("present with a subject key is rejected")
    func presentWithSubjectKeyRejected() {
        // Given
        let yaml = """
        name: present-with-of
        inputs:
          k: string
        steps:
          - id: gated
            when:
              of: { ref: inputs.k }
              present: { ref: inputs.k }
            value: x
        """

        // When / Then — present takes its expression directly, without `of`
        #expect(throws: DecodingError.self) {
            try SpecLoader.testing.load(yaml)
        }
    }

    @Test("a predicate survives an encode/decode round trip")
    func predicateRoundTripsThroughCoding() throws {
        // Given
        let condition = Condition.allOf([
            .predicate(
                of: .ref(path("inputs.left")),
                operator: .is,
                operand: .ref(path("inputs.right"))
            ),
            .predicate(of: .ref(path("inputs.k")), operator: .present, operand: nil)
        ])

        // When
        let data = try JSONEncoder().encode(condition)
        let decoded = try JSONDecoder().decode(Condition.self, from: data)

        // Then
        #expect(decoded.referencedPaths == condition.referencedPaths)
    }

    @Test("referenced paths cover both sides of a predicate")
    func referencedPathsCoverBothSides() {
        // Given
        let condition = Condition.predicate(
            of: .ref(path("inputs.left")),
            operator: .is,
            operand: .ref(path("inputs.right"))
        )

        // Then
        #expect(condition.referencedPaths == [path("inputs.left"), path("inputs.right")])
    }
}
