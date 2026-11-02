//
//  DocumentTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/18/26.
//

import Foundation
import Testing
import Warp
import WarpSyntax
import WarpYAML
@testable import Forge

// A reference nobody runs drifts, and the drift is invisible until an author
// writes what it says and the build refuses. These read `document/Spec.md` and
// hold it to the code: the verbs it documents are the verbs the Forge library
// declares, each with the signature the library writes, and the workflow it
// prints is one that loads, builds and runs.
@Suite("The spec reference matches the Forge library")
struct DocumentTests {
    // The reference, read as data: which words it documents and which workflows it
    // prints whole: the ones tagged ```yaml runnable, so an example that is a
    // fragment rather than a workflow is not mistaken for one.
    private struct SpecDocument {
        // MARK: - Property
        let sections: Set<String>
        let workflows: [String]
    
        // Each section's first paragraph, the verb's signature line, its lines
        // joined by a space.
        let signatures: [String: String]
    
        // MARK: - Initializer
        init() {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // Vocabulary
                .deletingLastPathComponent()   // Host
                .deletingLastPathComponent()   // Service
                .deletingLastPathComponent()   // ForgeTests
                .deletingLastPathComponent()   // Tests
                .deletingLastPathComponent()   // package
                .deletingLastPathComponent()   // repository root
                .appendingPathComponent("document/Spec.md")
            let text = try! String(contentsOf: url, encoding: .utf8)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    
            var sections: Set<String> = []
            var workflows: [String] = []
            var signatures: [String: String] = [:]
            var fence: [String]?
            var section: String?
    
            for line in lines {
                if line.hasPrefix("### `"), line.hasSuffix("`") {
                    section = String(line.dropFirst(5).dropLast())
                    sections.insert(section ?? "")
    
                    continue
                }
    
                if let open = section {
                    if line.isEmpty, signatures[open] != nil {
                        section = nil
                    } else if !line.isEmpty {
                        signatures[open] = [signatures[open], String(line)].compactMap { part in part }.joined(separator: " ")
                    }
                }
    
                if line.hasPrefix("```") {
                    // Closing a block: keep it when it stands as a whole document.
                    if let collected = fence {
                        workflows.append(collected.joined(separator: "\n"))
    
                        fence = nil
                    } else if line == "```yaml runnable" {
                        fence = []
                    }
    
                    continue
                }
    
                if fence != nil { fence?.append(String(line)) }
            }
    
            self.sections = sections
            self.workflows = workflows
            self.signatures = signatures
        }
    
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    private let document = SpecDocument()

    // MARK: - Lifecycle
    // MARK: - Test
    @Test("every verb the Forge library declares has a section")
    func everyWordIsDocumented() throws {
        let missing = Set(try ForgeVocabulary.shipped.get().verbs.map(\.spelling))
            .subtracting(document.sections)
            .sorted()

        #expect(missing.isEmpty, "documented nowhere in Spec.md: \(missing)")
    }

    @Test("every verb the reference documents is one the Forge library declares")
    func everyDocumentedWordExists() throws {
        let declared = Set(try ForgeVocabulary.shipped.get().verbs.map(\.spelling))
        let phantom = document.sections.subtracting(declared).sorted()

        #expect(phantom.isEmpty, "Spec.md documents verbs the Forge library does not declare: \(phantom)")
    }

    @Test("every verb's signature line says what lib/Forge.yaml declares: parameters and their types, what it returns, const and its failures")
    func everySignatureIsTheLibrarys() throws {
        // Given
        guard
            case let .dictionary(library) = try ValueBridge.value(try YAMLSpec.decode(JSONValue.self, from: Data(Library.text.utf8))),
            case let .dictionary(procedures)? = library[key: .string("procedures")]
        else {
            Issue.record("lib/Forge.yaml declares its verbs under procedures")
            return
        }

        for (key, declared) in procedures.entries {
            guard case let .string(verb) = key, case let .dictionary(procedure) = declared else { continue }

            // When
            let sut = try #require(document.signatures["Forge.\(verb)"], "Spec.md has no signature line for \(verb)")

            // Then
            #expect(sut.hasPrefix("`\(Self.signature(of: procedure, named: verb))`"), "\(verb): \(sut)")
            #expect(sut.contains("const") == (procedure[key: .string("const")] == .bool(true)), "\(verb): \(sut)")

            switch procedure[key: .string("failing")] {
            case let .string(failing)?:
                #expect(sut.contains("failing \(failing)"), "\(verb): \(sut)")

            case let .array(failures)?:
                let written = failures.map { failure in "`\(ValueBridge.text(failure))`" }.joined(separator: ", ")

                #expect(sut.contains("failing \(written)"), "\(verb): \(sut)")

            default:
                #expect(!sut.contains("failing"), "\(verb): \(sut)")
            }
        }
    }

    @Test("every complete workflow the reference prints loads and builds")
    func theExamplesLoad() async throws {
        // Given
        let sut = document.workflows

        // Then
        #expect(!sut.isEmpty, "Spec.md carries no complete workflow to check")

        for written in sut {
            // When, Then
            await #expect(throws: Never.self) { _ = try await Self.image(of: written) }
        }
    }

    @Test("a workflow whose entry is not a public `main` does not pass as a complete workflow")
    func aRefusedExampleDoesNotLoad() async throws {
        // Given
        let written = """
            procedures:
              tour:
                access: public
                returns: Int
                result: 1
            """

        // When
        let sut = await #expect(throws: WorkflowValidationError.self) { try await Self.image(of: written) }

        // Then
        #expect(sut?.message.contains("'\(Workflow.entry)'") == true, "\(String(describing: sut))")
    }

    @Test("the reference's tour runs, and returns what it says it does")
    func theTourRuns() async throws {
        // Given
        let written = try #require(document.workflows.first)
        let image = try await Self.image(of: written)

        // When
        let returned = try await Executor().run(image, entry: try Warp.Name(Workflow.entry), arguments: ["who": .null])
        let sut = try ValueBridge.fields(returned)

        // Then
        #expect(sut["greeting"] == .string("hello, world"))
        #expect(sut["branch"] == .string("took-a"))
        #expect(sut["loop"] == .int(2))
        #expect(sut["walk"] == .array([.string("0:one"), .string("1:two")]))
        #expect(try ValueBridge.json(sut["parallel"] ?? .null) == .object(["left": .int(1), "right": .int(2)]))
        #expect(sut["rescued"] == .string("rescued: bail out"))
    }

    // MARK: - Public
    // MARK: - Private
    // Read and built the way the daemon reads a workflow file, held to Forge's
    // convention (`WorkflowBuilder.convention`: a public procedure `main` a run
    // starts from), so an example the daemon would refuse cannot pass here.
    private static func image(of written: String) async throws -> Image {
        try await WorkflowBuilder.shipped.get().workflow(at: "document/Spec.md", text: written).image
    }

    // A verb's signature as the library writes it: each parameter's name and
    // the type it writes, whatever default it takes, and what it returns.
    private static func signature(of procedure: Value.Dictionary, named verb: String) -> String {
        var parameters: [Value] = []

        if case let .array(declared)? = procedure[key: .string("parameters")] { parameters = declared }

        let written = parameters.compactMap { parameter -> String? in
            guard case let .dictionary(pair) = parameter, let (name, declared) = pair.entries.first else { return nil }

            switch declared {
            case let .dictionary(declaration):
                return "\(ValueBridge.text(name)): \(ValueBridge.text(declaration[key: .string("type")] ?? .null))"

            default:
                return "\(ValueBridge.text(name)): \(ValueBridge.text(declared))"
            }
        }
        let returns = ValueBridge.text(procedure[key: .string("returns")] ?? .null)

        return "\(verb)(\(written.joined(separator: ", "))) -> \(returns)"
    }
}
