//
//  ScopeLookupTests.swift
//  SpecTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Spec

@Suite
struct ScopeLookupTests {
    // MARK: - Property
    private let sut = Scope(
        inputs: ["name": .string("spec"), "items": .array([.int(1), .int(2), .int(3)])],
        contexts: ["run": ["id": .string("r-1")]],
        bindings: [
            "step": .object(["out": .string("done"), "list": .array([.string("a")])]),
            "index": .int(1)
        ]
    )

    // MARK: - Initializer
    // MARK: - Test
    @Test("an existing path returns its value")
    func existingPathReturnsValue() {
        #expect(sut.lookup(path("inputs.name")) == .found(.string("spec")))
        #expect(sut.lookup(path("run.id")) == .found(.string("r-1")))
        #expect(sut.lookup(path("step.out")) == .found(.string("done")))
        #expect(sut.lookup(path("inputs.items[1]")) == .found(.int(2)))
    }

    @Test("a missing key answers absent")
    func missingKeyReturnsAbsent() {
        #expect(sut.lookup(path("inputs.missing")) == .absent)
        #expect(sut.lookup(path("nowhere")) == .absent)
        #expect(sut.lookup(path("inputs.items[9]")) == .absent)
    }

    @Test("shape misuse is unfit, not absent")
    func shapeMisuseReturnsUnfit() {
        // Then — drilling a field into a string is an author error, not missing data
        guard case .unfit = sut.lookup(path("inputs.name.foo")) else {
            Issue.record("expected unfit")

            return
        }

        guard case .unfit = sut.lookup(path("inputs.name[0]")) else {
            Issue.record("expected unfit for indexing into a string")

            return
        }
    }

    @Test("count derives from countable values")
    func countDerivesFromCountable() {
        #expect(sut.lookup(path("inputs.items.count")) == .found(.int(3)))
        #expect(sut.lookup(path("inputs.name.count")) == .found(.int(4)))
        #expect(sut.lookup(path("step.count")) == .found(.int(2)))
    }

    @Test("an index-reference segment resolves from a binding")
    func indexReferenceResolvesFromBinding() {
        #expect(sut.lookup(path("inputs.items[${index}]")) == .found(.int(2)))
    }
}
