//
//  ForgeSpecTests.swift
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
struct ForgeSpecTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("what ships is what lib/Forge.yaml holds")
    func whatShipsIsWhatTheRepositoryHolds() throws {
        // Given
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Warp
            .deletingLastPathComponent()   // Workflow
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

    @Test("each verb of the library stands over the native of its name, and every native has one")
    func everyVerbStandsOverItsNative() throws {
        // Given
        let natives = Set(try ForgeSpec.natives().procedures.keys.map(\.spelling))

        // When
        let sut = Set(try ForgeSpec.verbs().map(\.spelling))

        // Then
        #expect(Set(sut.map { verb in verb.replacingOccurrences(of: "Forge.", with: "Forge.Native.") }) == natives)
    }

    @Test("the library builds with the natives and the standard vocabulary")
    func theLibraryBuilds() async throws {
        // Given
        let sut = try ForgeSpec.linkables()

        // When / Then
        _ = try await Builder().build(sut)
    }

    @Test("a workflow names a verb by its short name and its arguments by name, and a default fills the rest")
    func aVerbIsCalledByNameWithItsDefaults() async throws {
        // Given
        let sut = try ForgeSpec.frontend()

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

        _ = try await Builder().build([module] + ForgeSpec.linkables())
    }

    @Test("a native takes the value the library settles, so null where the library holds a default is refused by the build")
    func aNativeTakesTheSettledDefault() async throws {
        // Given
        let document = try ForgeSpec.frontend().document(from: workflowFile("""
        returns: String
        failing: [nonzero_exit, timeout]
        result: { call: { procedure: Forge.Native.shell, arguments: [ [ls], null, null, null, null ] } }
        """, named: "raw"))
        let module = try Loader().load(document, identity: try Identity.of(document))

        // When / Then
        await #expect(throws: (any Error).self) {
            _ = try await Builder().build([module] + ForgeSpec.linkables())
        }
    }

    // MARK: - Public
    // MARK: - Private
}
