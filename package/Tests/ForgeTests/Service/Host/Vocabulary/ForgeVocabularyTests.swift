//
//  ForgeVocabularyTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/24/26.
//

import Foundation
import Testing
import Warp
import WarpSyntax
import WarpYAML
@testable import Forge

@Suite("Forge's library over the native verbs")
struct ForgeVocabularyTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("what ships is what lib/Forge.yaml holds")
    func whatShipsIsWhatTheRepositoryHolds() throws {
        // Given
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Vocabulary
            .deletingLastPathComponent()   // Host
            .deletingLastPathComponent()   // Service
            .deletingLastPathComponent()   // ForgeTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package
            .deletingLastPathComponent()   // the repository
            .appendingPathComponent("lib")
            .appendingPathComponent("Forge.yaml")

        // When
        let written = try String(contentsOf: file, encoding: .utf8)

        // Then
        #expect(
            Library.text == written.trimmingCharacters(in: .newlines),
            "lib/Forge.yaml differs from what ships. Run tool/embed-library.sh"
        )
    }

    @Test("each verb of the library is one call of the native of its name, handing its parameters in order, and every native has one")
    func everyVerbCallsItsNative() throws {
        // Given
        let document = try ForgeVocabulary.shipped.get().library
        let library = try Loader().load(document)
        let natives = Set(try ForgeVocabulary.natives().procedures.keys)

        for (name, sut) in library.procedures {
            // When
            let sent = sut.body.statements.compactMap { statement -> Call? in
                switch statement.expression {
                case let .call(call), let .leave(.procedure(.call(call)?)):
                    natives.contains(call.selector) ? call : nil

                default:
                    nil
                }
            }
            let handed = sent.first?.arguments.map { argument -> Warp.Name? in
                guard case let .reference(path) = argument else { return nil }

                return path.head
            }

            // Then
            #expect(sent.map(\.selector.spelling) == [name.spelling.replacingOccurrences(of: "Forge.", with: "Forge.Native.")])
            #expect(handed == sut.signature.parameters.map(\.name), "\(name)")
        }

        #expect(Set(library.procedures.keys.map { name in name.spelling.replacingOccurrences(of: "Forge.", with: "Forge.Native.") }) == Set(natives.map(\.spelling)))
    }

    @Test("the library builds with the natives and the standard vocabulary")
    func theLibraryBuilds() async throws {
        // Given
        let sut = try ForgeVocabulary.shipped.get().linkables

        // When / Then
        _ = try await Builder().build(sut)
    }

    @Test("a workflow names a verb by its short name and its arguments by name, and a default fills the rest")
    func aVerbIsCalledByNameWithItsDefaults() async throws {
        // Given
        let sut = try ForgeVocabulary.shipped.get().frontend

        // When
        let document = try sut.decoded(from: workflowFile("""
        returns: String
        failing: [nonzero_exit, timeout]
        result: { call: { procedure: shell, arguments: { timeout: 30, command: [ls] } } }
        """, named: "listing"))

        // Then
        guard case let .dictionary(held) = document else {
            Issue.record("a document is a dictionary")
            return
        }

        #expect(held[key: .string("imports")] == .array([.string("Forge.shell")]))

        let module = try Loader().load(document)

        _ = try await Builder().build([module] + ForgeVocabulary.shipped.get().linkables)
    }

    @Test("a native takes the value the library settles, so null where the library holds a default is refused by the build at that argument's line")
    func aNativeTakesTheSettledDefault() async throws {
        // Given
        let builder = try WorkflowBuilder.shipped.get()
        let spent = try builder.vocabulary.frontend.document(from: workflowFile("""
        returns: String
        failing: [nonzero_exit, timeout]
        result: { call: { procedure: Forge.Native.shell, arguments: [ [ls], null, null, null, null ] } }
        """, named: "raw"))
        let document = try BinaryEncoding().value(from: spent.document)
        let sut = DocumentOrigin(identity: try Identity.of(document), origin: spent.origin)
        let module = try Loader().load(document)

        // When
        let error = await #expect(throws: (any Error).self) {
            _ = try await builder.compiled([module])
        }

        // Then
        let described = sut.described(try #require(error))

        #expect(described.hasPrefix("6:79: "), "\(described)")
        #expect(described.contains("with env, which holds Null where Dictionary<String, String> is declared"), "\(described)")
    }

    // MARK: - Public
    // MARK: - Private
}
