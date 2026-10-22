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
@testable import Forge

// A reference nobody runs drifts, and the drift is invisible until an author
// writes what it says and the build refuses. These read `document/Spec.md` and
// hold it to the code: the verbs it documents are the verbs the Forge module
// declares, and the workflow it prints is one that loads, builds and runs.
@Suite("The spec reference matches the Forge module")
struct DocumentTests {
    // MARK: - Property
    private let document = SpecDocument()

    // MARK: - Lifecycle
    // MARK: - Test
    @Test("every verb the Forge module declares has a section")
    func everyWordIsDocumented() throws {
        let missing = Set(try ForgeSpec.vocabulary().procedures.keys.map(\.spelling))
            .subtracting(document.sections)
            .sorted()

        #expect(missing.isEmpty, "documented nowhere in Spec.md: \(missing)")
    }

    @Test("every verb the reference documents is one the Forge module declares")
    func everyDocumentedWordExists() throws {
        let declared = Set(try ForgeSpec.vocabulary().procedures.keys.map(\.spelling))
        let phantom = document.sections.subtracting(declared).sorted()

        #expect(phantom.isEmpty, "Spec.md documents verbs the Forge module does not declare: \(phantom)")
    }

    @Test("every complete workflow the reference prints loads and builds")
    func theExamplesLoad() async throws {
        #expect(!document.workflows.isEmpty, "Spec.md carries no complete workflow to check")

        for written in document.workflows {
            _ = try await Self.image(of: written)
        }
    }

    @Test("the reference's tour runs, and returns what it says it does")
    func theTourRuns() async throws {
        let written = try #require(document.workflows.first)
        let (image, name) = try await Self.image(of: written)
        let returned = try await Warp.Executor().run(image, entry: name, arguments: ["who": .null])
        let result = try ValueBridge.fields(returned)

        #expect(result["greeting"] == .string("hello, world"))
        #expect(result["branch"] == .string("took-a"))
        #expect(result["loop"] == .int(2))
        #expect(result["walk"] == .array([.string("0:one"), .string("1:two")]))
        #expect(ValueBridge.json(result["parallel"] ?? .null) == .object(["left": .int(1), "right": .int(2)]))
        #expect(result["rescued"] == .string("rescued: bail out"))
    }

    // MARK: - Public
    // MARK: - Private
    // Loaded and built the way the catalog does it, including Forge's own rule
    // on top of the language, one procedure per file, so an example the daemon
    // would refuse cannot pass here.
    private static func image(of written: String) async throws -> (Image, Name) {
        let document = try ForgeSpec.frontend().document(from: written)
        let module = try Loader().load(document, identity: try Identity.of(document))

        guard module.procedures.count == 1, let name = module.procedures.keys.first else {
            throw ExecutionError("a complete workflow in Spec.md declares one procedure")
        }

        return (try await Builder().build([module] + ForgeSpec.linkables()), name)
    }
}

// The reference, read as data: which words it documents and which workflows it
// prints whole: the ones tagged ```yaml runnable, so an example that is a
// fragment rather than a workflow is not mistaken for one.
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
