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
        let document = try ForgeVocabulary.library()
        let library = try Loader().load(document, identity: try Identity.of(document))
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
            let handed = sent.first?.arguments.map { argument -> Name? in
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
        let sut = try ForgeVocabulary.linkables()

        // When / Then
        _ = try await Builder().build(sut)
    }

    @Test("a workflow names a verb by its short name and its arguments by name, and a default fills the rest")
    func aVerbIsCalledByNameWithItsDefaults() async throws {
        // Given
        let sut = try ForgeVocabulary.frontend()

        // When
        let document = try sut.document(from: workflowFile("""
        returns: String
        failing: [nonzero_exit, timeout]
        result: { call: { procedure: shell, arguments: { timeout: 30, command: [ls] } } }
        """, named: "listing"))

        // Then
        guard case let .dictionary(held) = document else {
            Issue.record("a document is a map")
            return
        }

        #expect(held[key: .string("imports")] == .array([.string("Forge.shell")]))

        let module = try Loader().load(document, identity: try Identity.of(document))

        _ = try await Builder().build([module] + ForgeVocabulary.linkables())
    }

    @Test("a native takes the value the library settles, so null where the library holds a default is refused by the build at that argument")
    func aNativeTakesTheSettledDefault() async throws {
        // Given
        let document = try ForgeVocabulary.frontend().document(from: workflowFile("""
        returns: String
        failing: [nonzero_exit, timeout]
        result: { call: { procedure: Forge.Native.shell, arguments: [ [ls], null, null, null, null ] } }
        """, named: "raw"))
        let module = try Loader().load(document, identity: try Identity.of(document))

        // When
        let error = await #expect(throws: (any Error).self) {
            _ = try await Builder().build([module] + ForgeVocabulary.linkables())
        }

        // Then
        let refusal = try #require(error as? any WarpError)

        #expect(refusal.place?.rendered?.hasSuffix("procedures.raw.body[0].leave.arguments[2]") == true, "\(refusal)")
        #expect(refusal.message.contains("with env, which holds Null where Dictionary<String, String> is declared"), "\(refusal)")
    }

    // MARK: - Public
    // MARK: - Private
}
