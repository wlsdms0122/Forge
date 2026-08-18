//
//  DocumentTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/18/26.
//

import Foundation
import Testing
import Warp
import WarpIR
import WarpYAML
@testable import Forge

// A reference nobody runs drifts, and the drift is invisible until an author
// writes what it says and the load refuses. These read `document/Spec.md` and
// hold it to the decoder: the words it documents are the words that exist, and
// the workflow it prints is one that loads, links and runs.
@Suite("The spec reference matches the decoder")
struct DocumentTests {
    // MARK: - Property
    private let document = SpecDocument()

    // MARK: - Lifecycle
    // MARK: - Test
    @Test("every construct the loader registers has a section")
    func everyWordIsDocumented() throws {
        let missing = Set(ForgeSpec.loader().registry.keys)
            .subtracting(document.sections)
            .sorted()

        #expect(missing.isEmpty, "documented nowhere in Spec.md: \(missing)")
    }

    @Test("every section the reference documents is a construct that exists")
    func everyDocumentedWordExists() throws {
        let registered = Set(ForgeSpec.loader().registry.keys)

        // Sections name constructs; the reference also has prose headings, so
        // only a heading that looks like a word is held to this.
        let claimed = document.sections.filter { section in
            section.allSatisfy { character in character.isLetter || character == "_" }
        }

        let phantom = claimed.subtracting(registered).sorted()

        #expect(
            phantom.isEmpty,
            "Spec.md documents words the loader does not register: \(phantom)"
        )
    }

    @Test("every complete workflow the reference prints loads and links")
    func theExamplesLoad() throws {
        #expect(!document.workflows.isEmpty, "Spec.md carries no complete workflow to check")

        for written in document.workflows {
            _ = try Self.image(of: written)
        }
    }

    @Test("the reference's tour runs, and answers what it says it does")
    func theTourRuns() async throws {
        let written = try #require(
            document.workflows.first { text in text.hasPrefix("name: tour") }
        )
        let answer = try await ForgeSpec.loader().language
            .makeExecutor()
            .run(try Self.image(of: written), arguments: ["origin": .null, "run": .null])

        guard case let .object(result) = answer else {
            Issue.record("the example answered \(answer), not a record")

            return
        }

        // Spot the shapes a reader would copy the example for — that the words
        // ran at all, and that the two fan-out shapes answer differently.
        #expect(result["greeting"] == .string("hello, world"))
        #expect(result["size"] == .int(2))
        #expect(result["branch"] == .string("took-a"))
        #expect(result["loop"] == .int(2))
        #expect(result["walk"] == .array([.string("0:one"), .string("1:two")]))
        #expect(result["parallel"] == .object(["left": .int(1), "right": .int(2)]))
        #expect(result["race"] == .string("winner"))
        #expect(result["mapped"] == .array([.string("ONE"), .string("TWO")]))
        #expect(result["group"] == .string("grouped"))
        #expect(result["rescued"] == .string("rescued: bail out"))
        #expect(result["called"] == .string("hello, a"))
    }

    // MARK: - Private
    // Loaded and linked the way the catalog does it, including forge's own rule
    // on top of the language — one procedure, named after the file — so an
    // example the daemon would refuse cannot pass here.
    private static func image(of written: String) throws -> Image {
        let loader = ForgeSpec.loader()
        let module = try loader.load(ForgeSpec.seeding(document: YAMLParser().parse(written)))

        guard let name = module.name else {
            throw ExecutionError("a complete workflow in Spec.md declares no name")
        }

        guard Array(module.procedures.keys) == [name] else {
            throw ExecutionError(
                "a workflow file declares one procedure named after the file;"
                    + " '\(name)' declares \(module.procedures.keys.sorted())"
            )
        }

        return try loader.language.link([module] + ForgeSpec.linkables, entry: "\(name).\(name)")
    }
}

// The reference, read as data: which words it documents and which workflows it
// prints whole — the ones tagged ```yaml runnable, so an example that is a shape
// sketch rather than a workflow is not mistaken for one.
private struct SpecDocument {
    // MARK: - Property
    let sections: Set<String>
    let workflows: [String]

    // MARK: - Initializer
    init() {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ForgeTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("document/Spec.md")
        let text = try! String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        var sections: Set<String> = []
        var workflows: [String] = []
        var fence: [String]?

        for line in lines {
            if line.hasPrefix("### `"), line.hasSuffix("`") {
                sections.insert(String(line.dropFirst(5).dropLast()))
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
    }

    // MARK: - Public
    // MARK: - Private
}
