//
//  WorkflowReaderTests.swift
//  ForgeTests
//
//  Created by JSilver on 11/1/26.
//

import Foundation
import Testing
import Warp
@testable import Forge

@Suite("WorkflowReader Tests")
struct WorkflowReaderTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("reader")

    private let validBody = #"""
    failing: [nonzero_exit, timeout]
    body:
      - let: x
        value: { call: { procedure: shell, arguments: { command: ["/bin/echo", "ok"] } } }
    """#

    private let answerBody = "returns: Int\nresult: 42\n"

    private let brokenBody = "steps: notalist\n"

    // MARK: - Initializer
    // MARK: - Test
    // MARK: - Reading
    @Test("A broken file, once repaired, reads at its path")
    func aRepairedFileReadsAtItsPath() async throws {
        // Given
        let directory = try temporary.make("wf-repair")
        try writeWorkflow(brokenBody, named: "mender", in: directory)
        let sut = try WorkflowReader(directory: directory)
        let refusal = await #expect(throws: WorkflowValidationError.self) {
            try await sut.workflow(at: "mender.yaml")
        }

        // When
        try writeWorkflow(validBody, named: "mender", in: directory)
        let repaired = try await sut.workflow(at: "mender.yaml")

        // Then
        #expect(refusal?.message.hasPrefix("workflow 'mender.yaml' is broken: ") == true)
        #expect(repaired.path == "mender.yaml")
    }

    @Test("A file that loads and does not build is refused at build, and a workflow beside it still reads and runs")
    func aWorkflowThatDoesNotBuildIsRefused() async throws {
        // Given
        let directory = try temporary.make("wf-unbuilt")
        try writeWorkflow(answerBody, named: "ok", in: directory)
        try writeWorkflow("""
        result: { call: { procedure: Nowhere.missing } }
        """, named: "unbuilt", in: directory)
        let sut = try WorkflowReader(directory: directory)

        // When
        let refusal = await #expect(throws: WorkflowValidationError.self) {
            try await sut.workflow(at: "unbuilt.yaml")
        }
        let answer = try await run(sut, at: "ok.yaml")

        // Then
        #expect(refusal?.message.hasPrefix("workflow 'unbuilt.yaml' is broken: build: 4:5: ") == true)
        #expect(answer == .int(42))
    }

    @Test("A file's private procedure is a helper its main calls")
    func aPrivateProcedureIsAHelperItsMainCalls() async throws {
        // Given
        let directory = try temporary.make("wf-helper")
        try write("""
        procedures:
          main:
            access: public
            returns: Int
            result: { call: { procedure: scaled, arguments: { base: 21 } } }
          scaled:
            parameters: [ base: Int, by: { type: Int, default: 2 } ]
            returns: Int
            result: { of: { ref: base }, times: { ref: by } }
        """, named: "helped", in: directory)
        let sut = try WorkflowReader(directory: directory)

        // When
        let answer = try await run(sut, at: "helped.yaml")

        // Then
        #expect(answer == .int(42))
    }

    @Test("A file that declares no main is refused with what it declares")
    func aFileWithoutMainIsAFailure() async throws {
        // Given
        let directory = try temporary.make("wf-no-main")
        try write("""
        procedures:
          echo:
            access: public
            returns: Int
            result: 1
        """, named: "echo", in: directory)
        let sut = try WorkflowReader(directory: directory)

        // When
        let refusal = await #expect(throws: WorkflowValidationError.self) {
            try await sut.workflow(at: "echo.yaml")
        }

        // Then
        #expect(refusal?.message.hasPrefix("workflow 'echo.yaml' is broken: ") == true)
        #expect(refusal?.message.contains("declares the procedure 'main'") == true)
        #expect(refusal?.message.contains("found 'echo'") == true)
    }

    @Test("A main that is not public is refused")
    func aMainThatIsNotPublicIsAFailure() async throws {
        // Given
        let directory = try temporary.make("wf-private-main")
        try write("""
        procedures:
          main:
            returns: Int
            result: 1
        """, named: "hidden", in: directory)
        let sut = try WorkflowReader(directory: directory)

        // When
        let refusal = await #expect(throws: WorkflowValidationError.self) {
            try await sut.workflow(at: "hidden.yaml")
        }

        // Then
        #expect(refusal?.message.hasPrefix("workflow 'hidden.yaml' is broken: ") == true)
        #expect(refusal?.message.contains("'access: public'") == true)
    }

    @Test("A file is built again only when its mtime changed")
    func aFileIsBuiltAgainOnlyWhenItsMtimeChanged() async throws {
        // Given
        let directory = try temporary.make("wf-unchanged")
        let kept = directory.appendingPathComponent("kept.yaml")
        let touched = directory.appendingPathComponent("touched.yaml")
        let mtime = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try writeWorkflow(validBody, named: "kept", in: directory)
        try writeWorkflow(validBody, named: "touched", in: directory)

        for file in [kept, touched] {
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
        }

        let sut = try WorkflowReader(directory: directory)
        let before = try await sut.workflow(at: "kept.yaml")
        _ = try await sut.workflow(at: "touched.yaml")
        try writeWorkflow("returns: Int\nresult: 2\n", named: "kept", in: directory)
        try writeWorkflow("returns: Int\nresult: 2\n", named: "touched", in: directory)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: kept.path)
        try FileManager.default.setAttributes([.modificationDate: mtime.addingTimeInterval(1)], ofItemAtPath: touched.path)

        // When
        let after = try await sut.workflow(at: "kept.yaml")
        let reread = try await sut.workflow(at: "touched.yaml")

        // Then
        #expect(after.module.identity == before.module.identity)
        #expect(after.contract.returns == "Null")
        #expect(reread.contract.returns == "Int")
    }

    @Test("Files of one basename in different folders each declare main and each read at its own path")
    func filesOfOneBasenameInDifferentFoldersEachResolve() async throws {
        // Given
        let directory = try temporary.make("same-basename")

        for (folder, answer) in [("a", 1), ("b", 2)] {
            let url = directory.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try writeWorkflow("returns: Int\nresult: \(answer)\n", named: "dup", in: url)
        }

        let sut = try WorkflowReader(directory: directory)

        // When
        let first = try await sut.workflow(at: "a/dup.yaml")
        let second = try await sut.workflow(at: "b/dup.yaml")

        // Then
        #expect(first.path == "a/dup.yaml")
        #expect(second.path == "b/dup.yaml")
        #expect(try await run(sut, at: "a/dup.yaml") == .int(1))
        #expect(try await run(sut, at: "b/dup.yaml") == .int(2))
    }

    @Test("A file with an extension other than .yaml that is a valid workflow reads and runs")
    func aFileOfAnyExtensionReadsAndRuns() async throws {
        // Given
        let directory = try temporary.make("wf-extension")
        try workflowFile(answerBody).write(
            to: directory.appendingPathComponent("answer.workflow"),
            atomically: true, encoding: .utf8)
        let sut = try WorkflowReader(directory: directory)

        // When
        let answer = try await run(sut, at: "answer.workflow")

        // Then
        #expect(answer == .int(42))
    }

    @Test("A broken file or a data file in the root does not affect reading a workflow beside it")
    func otherFilesInTheRootDoNotAffectAWorkflow() async throws {
        // Given
        let directory = try temporary.make("wf-neighbours")
        try write("token: abc\nretries: 3\n", named: "settings", in: directory)
        try write("body: [", named: "torn", in: directory)
        try writeWorkflow(answerBody, named: "ok", in: directory)
        let sut = try WorkflowReader(directory: directory)

        // When
        let answer = try await run(sut, at: "ok.yaml")

        // Then
        #expect(answer == .int(42))
    }

    // MARK: - Absence
    @Test("A path with no file is not found")
    func aPathWithNoFileIsNotFound() async throws {
        // Given
        let directory = try temporary.make("wf-absent")
        try writeWorkflow(validBody, named: "a", in: directory)
        let sut = try WorkflowReader(directory: directory)

        // When
        let missing = await #expect(throws: WorkflowNotFound.self) {
            try await sut.workflow(at: "nope.yaml")
        }

        // Then
        #expect(missing?.message == "workflow not found: nope.yaml")
    }

    @Test("A directory is not a file, so a path to one is not found")
    func aDirectoryIsNotFound() async throws {
        // Given
        let directory = try temporary.make("wf-folder")
        let folder = directory.appendingPathComponent("bot")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writeWorkflow(validBody, named: "a", in: folder)
        let sut = try WorkflowReader(directory: directory)

        // When
        let missing = await #expect(throws: WorkflowNotFound.self) {
            try await sut.workflow(at: "bot")
        }

        // Then
        #expect(missing?.message == "workflow not found: bot")
    }

    @Test("A file deleted after it was read is not found on the next read")
    func aDeletedFileIsNotFound() async throws {
        // Given
        let directory = try temporary.make("wf-deleted")
        try writeWorkflow(validBody, named: "gone", in: directory)
        let sut = try WorkflowReader(directory: directory)
        _ = try await sut.workflow(at: "gone.yaml")
        try FileManager.default.removeItem(at: directory.appendingPathComponent("gone.yaml"))

        // When
        let missing = await #expect(throws: WorkflowNotFound.self) {
            try await sut.workflow(at: "gone.yaml")
        }

        // Then
        #expect(missing?.message == "workflow not found: gone.yaml")
    }

    @Test("An unreadable file is broken, never folded into absence")
    func anUnreadableFileIsBrokenNotAbsent() async throws {
        // Given
        let directory = try temporary.make("wf-unreadable")
        let file = directory.appendingPathComponent("ghost.yaml")
        try writeWorkflow(validBody, named: "ghost", in: directory)
        try chmod(file, 0o000)
        defer { try? chmod(file, 0o644) }
        let sut = try WorkflowReader(directory: directory)

        // When
        let refusal = await #expect(throws: WorkflowValidationError.self) {
            try await sut.workflow(at: "ghost.yaml")
        }

        // Then
        #expect(refusal?.message.hasPrefix("workflow 'ghost.yaml' is broken: ") == true)
    }

    // MARK: - Admission
    @Test("A path that escapes the root is refused and not read")
    func aPathThatEscapesTheRootIsRefused() async throws {
        // Given
        let outside = try temporary.make("wf-escape")
        let directory = try temporary.make("wf-escape/root")
        try writeWorkflow(answerBody, named: "x", in: outside)
        let sut = try WorkflowReader(directory: directory)

        // When
        let refusal = await #expect(throws: ResourceError.self) {
            try await sut.workflow(at: "../x.yaml")
        }

        // Then
        #expect(refusal?.message.contains("'../x.yaml'") == true)
    }

    @Test("A path with a hidden component is refused and not read")
    func aHiddenPathIsRefused() async throws {
        // Given
        let directory = try temporary.make("wf-hidden")
        let hidden = directory.appendingPathComponent(".private")
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try writeWorkflow(answerBody, named: "x", in: hidden)
        let sut = try WorkflowReader(directory: directory)

        // When
        let refusal = await #expect(throws: ResourceError.self) {
            try await sut.workflow(at: ".private/x.yaml")
        }

        // Then
        #expect(refusal?.message.contains("hidden component") == true)
    }

    @Test(
        "A path with an empty, '.' or '..' part is refused though the file it lands on exists and builds",
        arguments: ["a/../b.yaml", "./b.yaml", "a/./b.yaml", "a//b.yaml", "/b.yaml"]
    )
    func aPathWithADotPartIsRefused(path: String) async throws {
        // Given
        let directory = try temporary.make("wf-dots")
        let folder = directory.appendingPathComponent("a")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writeWorkflow(answerBody, named: "b", in: directory)
        try writeWorkflow(answerBody, named: "b", in: folder)
        let sut = try WorkflowReader(directory: directory)

        // When
        let refusal = await #expect(throws: ResourceError.self) {
            try await sut.workflow(at: path)
        }

        // Then
        #expect(refusal?.message.contains("'\(path)'") == true)
        #expect(try await run(sut, at: "b.yaml") == .int(42))
    }

    @Test("A file spelled as the inline sigil is refused, so a grant for inline specs grants no file")
    func theInlineSigilNamesNoFile() async throws {
        // Given
        let directory = try temporary.make("wf-sigil")
        try workflowFile(answerBody).write(
            to: directory.appendingPathComponent(Workflow.inlineSigil),
            atomically: true, encoding: .utf8)
        let sut = try WorkflowReader(directory: directory)

        // When
        let refusal = await #expect(throws: ResourceError.self) {
            try await sut.workflow(at: Workflow.inlineSigil)
        }

        // Then
        #expect(refusal?.message.contains("names an inline spec") == true)
    }

    // MARK: - Bounds
    @Test("A file nested past the bound is refused at its line")
    func aDeeplyNestedFileIsRefused() async throws {
        // Given
        let directory = try temporary.make("wf-deep")
        try writeWorkflow("""
        returns: Any
        result: \(String(repeating: "[", count: 1_000))1\(String(repeating: "]", count: 1_000))
        """, named: "deep", in: directory)
        let sut = try WorkflowReader(directory: directory)

        // When
        let refusal = await #expect(throws: WorkflowValidationError.self) {
            try await sut.workflow(at: "deep.yaml")
        }

        // Then
        #expect(refusal?.message.hasPrefix("workflow 'deep.yaml' is broken: ") == true)
        #expect(refusal?.message.hasSuffix("the text nests deeper than 128 containers") == true)
    }

    @Test("An inline spec nested past the bound is refused")
    func aDeeplyNestedInlineSpecIsRefused() async throws {
        // Given
        let sut = try WorkflowReader(directory: nil)
        let result = (0..<129).reduce(JSONValue.int(1)) { nested, _ in .array([nested]) }

        do {

        // When
            _ = try await sut.inline(["returns": "Any", "result": result])

        // Then
            Issue.record("an inline spec nested past the bound is refused")
        } catch let refusal as WorkflowValidationError {
            #expect(refusal.message == "the text nests deeper than 128 containers")
        }
    }

    // MARK: - Public
    // MARK: - Private
    // The value the workflow at this path returns, run from the image the
    // reader built for it.
    private func run(_ sut: WorkflowReader, at path: String) async throws -> Warp.Value {
        let image = try await sut.image(of: try await sut.workflow(at: path))

        return try await Executor().run(image, entry: try Name(Workflow.entry), arguments: [:])
    }

    // A workflow file carries the module envelope; the other files in the
    // root are written as they are.
    private func writeWorkflow(_ body: String, named name: String, in directory: URL) throws {
        try write(workflowFile(body), named: name, in: directory)
    }

    private func write(_ body: String, named name: String, in directory: URL) throws {
        try body.write(to: directory.appendingPathComponent("\(name).yaml"),
            atomically: true, encoding: .utf8)
    }

    private func chmod(_ url: URL, _ mode: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }
}
