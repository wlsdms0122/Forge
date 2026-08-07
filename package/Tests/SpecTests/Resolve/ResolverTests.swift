//
//  ResolverTests.swift
//  SpecTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Spec

@Suite
struct ResolverTests {
    // MARK: - Property
    private let sut = Resolver(scope: Scope(
        inputs: [
            "count": .int(3),
            "maybe": .null,
            "record": .object(["a": .int(1)])
        ]
    ))

    // MARK: - Initializer
    // MARK: - Test
    @Test("ref resolution preserves the type")
    func refResolutionPreservesType() throws {
        // Given
        let reference = Reference.ref(path("inputs.count"))

        // When
        let value = try sut.resolve(reference)

        // Then
        #expect(value == .int(3))
    }

    @Test("a null value flows through a ref untouched")
    func nullPassesThroughRef() throws {
        // Given
        let reference = Reference.ref(path("inputs.maybe"))

        // When
        let value = try sut.resolve(reference)

        // Then
        #expect(value == .null)
    }

    @Test("a null binding inside format is unfit")
    func nullBindingInFormatThrowsUnfit() {
        // Given — interpolating a name means the author assumed a value exists
        let reference = Reference.format(
            [.text("amount="), .ref(path: [.key("m")])],
            with: ["m": .ref(path("inputs.maybe"))]
        )

        // When / Then
        #expect(throws: ReferenceUnfit.self) {
            try sut.resolve(reference)
        }
    }

    @Test("an absent path throws ReferenceNotFound")
    func absentPathThrowsNotFound() {
        // Given
        let reference = Reference.ref(path("inputs.gone"))

        // When / Then
        #expect(throws: ReferenceNotFound.self) {
            try sut.resolve(reference)
        }
    }

    @Test("a shape-misusing path throws ReferenceUnfit")
    func shapeMisuseThrowsUnfit() {
        // Given
        let reference = Reference.ref(path("inputs.count.field"))

        // When / Then
        #expect(throws: ReferenceUnfit.self) {
            try sut.resolve(reference)
        }
    }

    @Test("nested structure resolves element by element")
    func nestedStructureResolves() throws {
        // Given
        let reference = Reference.recordValue([
            "n": .ref(path("inputs.count")),
            "list": .arrayValue([.stringValue("x")])
        ])

        // When
        let value = try sut.resolve(reference)

        // Then
        #expect(value == .object(["n": .int(3), "list": .array([.string("x")])]))
    }

    @Test("format renders over its declared with bindings")
    func declaredBindingsRenderFormat() throws {
        // Given
        let reference = Reference.format(
            [.text("n="), .ref(path: [.key("n")])],
            with: ["n": .ref(path("inputs.count"))]
        )

        // When
        let value = try sut.resolve(reference)

        // Then
        #expect(value == .string("n=3"))
    }

    @Test("in a closed scope a binding named inputs is just a binding")
    func closedScopeServesBindingNamedInputs() throws {
        // Given — a closed surface has no reserved heads: a binding named
        // `inputs` is just a binding, not an empty reserved namespace
        let reference = Reference.format(
            [.text("who="), .ref(path: [.key("inputs")])],
            with: ["inputs": .ref(path("inputs.count"))]
        )

        // When
        let value = try sut.resolve(reference)

        // Then
        #expect(value == .string("who=3"))
    }

    @Test("a quoted payload passes verbatim, unevaluated")
    func quotedPayloadPassesVerbatim() throws {
        // Given — the payload is data: a ref-shaped object inside stays an object
        let reference = Reference.quoted(.object([
            "ref": .string("inputs.count"),
            "note": .string("${inputs.count}")
        ]))

        // When
        let value = try sut.resolve(reference)

        // Then — nothing evaluated, nothing rendered
        #expect(value == .object([
            "ref": .string("inputs.count"),
            "note": .string("${inputs.count}")
        ]))
    }
}
