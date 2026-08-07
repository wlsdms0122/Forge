//
//  SpecLibraryTests.swift
//  SpecTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Spec

@Suite
struct SpecLibraryTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("a host extends the library vocabulary with its own words")
    func hostVocabularyExtends() async throws {
        // Given — `count` and `contains` are library words, not language
        // structure; a host adds its own the same way
        let library = try SpecLibrary.standard
            .deriving(Derivation(key: "first") { value in
                guard case .array(let array) = value else { return nil }

                return array.first ?? .null
            })
            .asking(PredicateAtom(key: "longer_than") { resolved, operand, path in
                guard case .string(let text)? = resolved else { return false }
                guard case .int(let limit) = operand else { return false }

                return text.count > limit
            })
        let loader = SpecLoader(registry: SpecLoader.testing.registry, library: library)
        let spec = try loader.load("""
        name: extended
        inputs:
          names: array
        steps:
          - id: verdict
            branch:
              when:
                { of: { ref: "inputs.names.first" }, longer_than: 3 }
              then:
                steps:
                  - id: yes
                    value: long
                output: { ref: yes }
        outputs:
          result: { ref: verdict }
          head: { ref: inputs.names.first }
        """)
        let sut = Executor(library: library)

        // When
        let outputs = try await sut.run(
            spec,
            inputs: ["names": .array([.string("spectacle"), .string("ok")])]
        )

        // Then
        #expect(outputs["result"] == .string("long"))
        #expect(outputs["head"] == .string("spectacle"))
    }

    @Test("a loader-made executor speaks the vocabulary that validated the spec")
    func loaderMadeExecutorSharesVocabulary() async throws {
        // Given — the executor derived from the loader speaks the same vocabulary
        // that validated the spec
        let library = try SpecLibrary.standard.asking(
            PredicateAtom(key: "ends_with") { resolved, operand, path in
                guard case .string(let text)? = resolved else { return false }
                guard case .string(let suffix) = operand else { return false }

                return text.hasSuffix(suffix)
            }
        )
        let loader = SpecLoader(registry: SpecLoader.testing.registry, library: library)
        let spec = try loader.load("""
        name: custom-atom
        inputs:
          title: string
        steps:
          - id: gated
            when:
              { of: { ref: inputs.title }, ends_with: "!" }
            value: excited
        outputs:
          result: { ref: gated }
        """)
        let sut = loader.makeExecutor()

        // When
        let outputs = try await sut.run(spec, inputs: ["title": .string("hello!")])

        // Then
        #expect(outputs["result"] == .string("excited"))
    }

    @Test("a colliding library word is rejected at registration")
    func collidingLibraryWordRejected() throws {
        // Given / When / Then — one door, one policy: duplicates and reserved
        // core operator names are refused at registration
        #expect(throws: ValidationError.self) {
            try SpecLibrary.standard.asking(
                PredicateAtom(key: "contains") { _, _, _ in false }
            )
        }
        #expect(throws: ValidationError.self) {
            try SpecLibrary.standard.asking(
                PredicateAtom(key: "not") { _, _, _ in false }
            )
        }
        #expect(throws: ValidationError.self) {
            try SpecLibrary.standard.deriving(
                Derivation(key: "count") { _ in nil }
            )
        }
    }

    @Test("a claimed action key is never silently replaced")
    func claimedActionKeyRejected() {
        // Given / When / Then — a host must not silently replace `loop`
        #expect(throws: ValidationError.self) {
            try ActionRegistry.standard.registering(LoopAction.self)
        }
    }
}
