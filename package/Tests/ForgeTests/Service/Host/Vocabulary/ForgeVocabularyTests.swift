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
    @Test(
        "what ships is what lib holds",
        arguments: [
            ("Forge.yaml", Library.text),
            ("Native.interface.warpt", Library.nativeInterface)
        ]
    )
    func whatShipsIsWhatTheRepositoryHolds(file: String, shipped: String) throws {
        // Given
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Vocabulary
            .deletingLastPathComponent()   // Host
            .deletingLastPathComponent()   // Service
            .deletingLastPathComponent()   // ForgeTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package
            .deletingLastPathComponent()   // the repository
            .appendingPathComponent("lib")
            .appendingPathComponent(file)

        // When
        let written = try String(contentsOf: url, encoding: .utf8)

        // Then
        #expect(
            shipped == written.trimmingCharacters(in: .newlines),
            "lib/\(file) differs from what ships. Run tool/embed-library.sh"
        )
    }

    @Test("each verb of the library is one call of the native of its name, handing its parameters in order, and every native has one")
    func everyVerbCallsItsNative() throws {
        // Given
        let library = try Self.entries(of: try ForgeVocabulary.shipped.get().library, at: "procedures")
        let natives = Set(try ForgeVocabulary.natives().procedures.keys.map(\.spelling))

        for (name, sut) in library {
            // When
            let declared = try Self.entries(of: sut, at: "parameters").map { _, parameter in
                try Self.entries(of: parameter, at: nil).first { key, _ in key == "name" }?.value
            }
            let sent = Self.calls(in: sut).filter { procedure, _ in natives.contains(procedure) }
            let handed = sent.first?.arguments.map { argument -> Value? in
                guard case let .dictionary(reference) = argument else { return nil }

                return reference[key: .string("ref")]
            }

            // Then
            #expect(sent.map(\.procedure) == [name.replacingOccurrences(of: "Forge.", with: "Forge.Native.")])
            #expect(handed == declared, "\(name)")
        }

        #expect(Set(library.map { name, _ in name.replacingOccurrences(of: "Forge.", with: "Forge.Native.") }) == natives)
    }

    @Test("the natives declare what their interface declares, the library writes its calls against")
    func theNativesDeclareTheirInterface() throws {
        // Given
        let interface = try Loader().interface(TextEncoding().value(from: Library.nativeInterface))

        // When
        let sut = try ForgeVocabulary.natives()

        // Then
        #expect(sut.types == interface.types)
        #expect(sut.contracts == interface.contracts)
        #expect(sut.procedures.mapValues(\.signature) == interface.procedures.mapValues(\.signature))
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
        """))

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
        """, uses: ["Native"]))
        let document = try BinaryEncoding().value(from: spent.document)
        let sut = DocumentOrigin(identity: try Identity.of(document), origin: spent.origin)
        let module = try Loader().load(document)

        // When
        let error = await #expect(throws: (any Error).self) {
            _ = try await builder.image(of: module)
        }

        // Then
        let described = sut.described(try #require(error))

        #expect(described.hasPrefix("7:79: "), "\(described)")
        #expect(described.contains("with env, which holds Null where Dictionary<String, String> is declared"), "\(described)")
    }

    // MARK: - Public
    // MARK: - Private
    // The entries of the mapping under `key` of a document's mapping, or of
    // the value itself without one, a list read as its positions.
    private static func entries(of value: Value, at key: String?) throws -> [(key: String, value: Value)] {
        let held: Value

        if let key {
            guard case let .dictionary(mapping) = value, let found = mapping[key: .string(key)] else { return [] }

            held = found
        } else {
            held = value
        }

        switch held {
        case let .dictionary(mapping):
            return mapping.entries.compactMap { key, value in
                guard case let .string(name) = key else { return nil }

                return (name, value)
            }

        case let .array(items):
            return items.enumerated().map { position, item in ("\(position)", item) }

        default:
            Issue.record("\(key ?? "the value") is a mapping or a list")
            return []
        }
    }

    // Every call the document's value writes, by the procedure it names,
    // with the arguments it hands.
    private static func calls(in value: Value) -> [(procedure: String, arguments: [Value])] {
        switch value {
        case let .dictionary(mapping):
            var found: [(procedure: String, arguments: [Value])] = []

            if
                case let .dictionary(call)? = mapping[key: .string("call")],
                case let .string(procedure)? = call[key: .string("procedure")]
            {
                guard case let .array(arguments)? = call[key: .string("arguments")] else {
                    found.append((procedure, []))

                    return found + mapping.values.flatMap { value in calls(in: value) }
                }

                found.append((procedure, arguments))
            }

            return found + mapping.values.flatMap { value in calls(in: value) }

        case let .array(items):
            return items.flatMap { item in calls(in: item) }

        default:
            return []
        }
    }
}
