//
//  CatalogGenerationTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
import Warp
@testable import Forge

@Suite("CatalogGeneration Tests")
struct CatalogGenerationTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("catalog")

    private let validBody = #"""
    failing: [nonzero_exit, timeout]
    body:
      - let: x
        value: { call: { procedure: shell, arguments: { command: ["/bin/echo", "ok"] } } }
    """#
    
    private let brokenBody = "steps: notalist\n"
    
    // MARK: - Initializer
    // MARK: - Test
    // MARK: - WorkflowCatalog
    @Test("A repaired definition cannot vanish from the catalog")
    func repairedDefinitionCannotVanishFromTheCatalog() async throws {
        // Given
        let directory = try temporary.make("wf-repair")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeWorkflow(brokenBody, named: "mender", in: directory)
        let catalog = try WorkflowCatalog(directory: directory)

        // When
        var snapshot = await catalog.reload()

        // Then
        #expect(snapshot.entries.isEmpty)
        #expect(snapshot.failures.map(\.path) == ["mender.yaml"])
        try writeWorkflow(validBody, named: "mender", in: directory)
        snapshot = await catalog.reload()
        try assertAccountedForExactlyOnce(snapshot, in: directory)
        #expect(snapshot.entries.map(\.path) == ["mender.yaml"])
        #expect(snapshot.failures.isEmpty)
    }
    
    @Test("Live entries and failures do not overlap")
    func catalogEntriesAndFailuresAreDisjoint() async throws {
        // Given
        let directory = try temporary.make("wf-disjoint")
        defer { try? FileManager.default.removeItem(at: directory) }

        // When
        try writeWorkflow(validBody, named: "ok", in: directory)
        try writeWorkflow(brokenBody, named: "bad", in: directory)
        let snapshot = try await WorkflowCatalog(directory: directory).reload()
        try assertAccountedForExactlyOnce(snapshot, in: directory)

        // Then
        #expect(snapshot.entries.map(\.path) == ["ok.yaml"])
        #expect(snapshot.failures.map(\.path) == ["bad.yaml"])
    }
    
    @Test("A workflow that loads and does not build is a failure, and the others still build and run")
    func aWorkflowThatDoesNotBuildIsLeftOut() async throws {
        // Given
        let directory = try temporary.make("wf-unbuilt")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeWorkflow(validBody, named: "ok", in: directory)
        try writeWorkflow("""
        result: { call: { procedure: Nowhere.missing } }
        """, named: "unbuilt", in: directory)
        let sut = try WorkflowCatalog(directory: directory)

        // When
        let snapshot = await sut.reload()

        // Then
        try assertAccountedForExactlyOnce(snapshot, in: directory)
        #expect(snapshot.entries.map(\.path) == ["ok.yaml"])
        #expect(snapshot.failures.map(\.path) == ["unbuilt.yaml"])
        #expect(snapshot.failures.first?.reason.hasPrefix("build: 4:5: ") == true)

        guard case .invalid = await sut.resolve("unbuilt.yaml") else {
            Issue.record("a workflow that does not build resolves as broken")
            return
        }

        _ = try await sut.image(of: try await sut.workflow(at: "ok.yaml"))
    }

    @Test("A file's private procedure is a helper its main calls")
    func aPrivateProcedureIsAHelperItsMainCalls() async throws {
        // Given
        let directory = try temporary.make("wf-helper")
        defer { try? FileManager.default.removeItem(at: directory) }
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
        let sut = try WorkflowCatalog(directory: directory)

        // When
        let snapshot = await sut.reload()
        let image = try await sut.image(of: try await sut.workflow(at: "helped.yaml"))
        let answer = try await Executor().run(image, entry: try Name(Workflow.entry), arguments: [:])

        // Then
        #expect(snapshot.failures.isEmpty)
        #expect(snapshot.entries.map(\.path) == ["helped.yaml"])
        #expect(answer == .int(42))
    }

    @Test("A file that declares no main is a failure that names what it declares")
    func aFileWithoutMainIsAFailure() async throws {
        // Given
        let directory = try temporary.make("wf-no-main")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeWorkflow(validBody, named: "ok", in: directory)
        try write("""
        procedures:
          echo:
            access: public
            returns: Int
            result: 1
        """, named: "echo", in: directory)
        let sut = try WorkflowCatalog(directory: directory)

        // When
        let snapshot = await sut.reload()

        // Then
        try assertAccountedForExactlyOnce(snapshot, in: directory)
        #expect(snapshot.entries.map(\.path) == ["ok.yaml"])
        #expect(snapshot.failures.map(\.path) == ["echo.yaml"])
        #expect(snapshot.failures.first?.reason.contains("declares the procedure 'main'") == true)
        #expect(snapshot.failures.first?.reason.contains("echo") == true)
    }

    @Test("A main that is not public is a failure")
    func aMainThatIsNotPublicIsAFailure() async throws {
        // Given
        let directory = try temporary.make("wf-private-main")
        defer { try? FileManager.default.removeItem(at: directory) }
        try write("""
        procedures:
          main:
            returns: Int
            result: 1
        """, named: "hidden", in: directory)
        let sut = try WorkflowCatalog(directory: directory)

        // When
        let snapshot = await sut.reload()

        // Then
        #expect(snapshot.entries.isEmpty)
        #expect(snapshot.failures.map(\.path) == ["hidden.yaml"])
        #expect(snapshot.failures.first?.reason.contains("'access: public'") == true)

        guard case .invalid = await sut.resolve("hidden.yaml") else {
            Issue.record("a file whose main is not public resolves as broken")
            return
        }
    }

    @Test("A reload reads again only the files whose mtime changed")
    func aReloadReadsAgainOnlyChangedFiles() async throws {
        // Given
        let directory = try temporary.make("wf-unchanged")
        defer { try? FileManager.default.removeItem(at: directory) }
        let kept = directory.appendingPathComponent("kept.yaml")
        let touched = directory.appendingPathComponent("touched.yaml")
        let mtime = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try writeWorkflow(validBody, named: "kept", in: directory)
        try writeWorkflow(validBody, named: "touched", in: directory)
        for file in [kept, touched] {
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
        }
        let sut = try WorkflowCatalog(directory: directory)
        let before = try await sut.workflow(at: "kept.yaml")
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

    @Test("A file nested past the bound is refused at its line")
    func aDeeplyNestedFileIsRefused() async throws {
        // Given
        let directory = try temporary.make("wf-deep")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeWorkflow(validBody, named: "ok", in: directory)
        try writeWorkflow("""
        returns: Any
        result: \(String(repeating: "[", count: 1_000))1\(String(repeating: "]", count: 1_000))
        """, named: "deep", in: directory)
        let sut = try WorkflowCatalog(directory: directory)

        // When
        let snapshot = await sut.reload()

        // Then
        #expect(snapshot.entries.map(\.path) == ["ok.yaml"])
        #expect(snapshot.failures.map(\.path) == ["deep.yaml"])
        #expect(snapshot.failures.first?.reason.hasSuffix("the text nests deeper than 128 containers") == true)
    }

    @Test("An inline spec nested past the bound is refused")
    func aDeeplyNestedInlineSpecIsRefused() async throws {
        // Given
        let sut = try WorkflowCatalog(directory: nil)
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

    @Test("A scan obstruction rides in the same observation")
    func scanObstructionRidesTheSameObservation() async throws {
        // Given
        let directory = try temporary.make("wf-obstruction")
        let closed = directory.appendingPathComponent("closed")
        try FileManager.default.createDirectory(at: closed, withIntermediateDirectories: true)
        try writeWorkflow(validBody, named: "visible", in: directory)
        try writeWorkflow(validBody, named: "hidden", in: closed)
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
            ofItemAtPath: closed.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                ofItemAtPath: closed.path)
            try? FileManager.default.removeItem(at: directory)
        }

        // When
        let snapshot = try await WorkflowCatalog(directory: directory).reload()

        // Then
        #expect(snapshot.entries.map(\.path) == ["visible.yaml"])
        #expect(snapshot.failures.contains { failure in failure.path == "<scan>" }, "the blocked enumeration never made it into the same response")
    }
    
    // MARK: - ScheduleStore
    @Test("The schedule snapshot is one observation — no mix of fragmented moments")
    func scheduleCatalogIsOneObservation() async throws {
        // Given
        let directory = try temporary.make("sched")
        defer { try? FileManager.default.removeItem(at: directory) }
        try write("workflow: w\nevery: 1h\n", named: "good", in: directory)
        try write("steps: notalist\n", named: "bad", in: directory)
        let store = ScheduleStore(directory: directory,
            enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let snapshot = await store.reload()

        // Then
        #expect(snapshot.entries.map(\.schedule.id) == ["good"])
        #expect(snapshot.failures.map(\.path) == ["bad.yaml"])
    }
    
    @Test("A schedule directory the scan could not enter is a failure at <scan>")
    func scheduleScanObstructionIsReported() async throws {
        // Given
        let directory = try temporary.make("sched-obstruction")
        let closed = directory.appendingPathComponent("closed")
        try FileManager.default.createDirectory(at: closed, withIntermediateDirectories: true)
        try write("workflow: w\nevery: 1h\n", named: "visible", in: directory)
        try write("workflow: w\nevery: 1h\n", named: "hidden", in: closed)
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
            ofItemAtPath: closed.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                ofItemAtPath: closed.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = ScheduleStore(directory: directory,
            enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let snapshot = await store.reload()

        // Then
        #expect(snapshot.entries.map(\.schedule.id) == ["visible"])
        #expect(snapshot.failures.map(\.path) == ["<scan>"])
        #expect(snapshot.failures.first?.reason.hasPrefix("schedule directory scan incomplete — closed") == true)
    }
    
    // MARK: - PolicyStore
    @Test("The policy snapshot is also one observation")
    func policyCatalogIsOneObservation() async throws {
        // Given
        let directory = try temporary.make("policy")
        defer { try? FileManager.default.removeItem(at: directory) }
        try "admin:alice:\n  - \"*\"\n".write(to: directory.appendingPathComponent("ok.yaml"),
            atomically: true, encoding: .utf8)

        // When
        let snapshot = await PolicyStore(directory: directory).reload()

        // Then
        #expect(snapshot.policy["admin:alice"] == ["*"])
        #expect(snapshot.failures.isEmpty)
    }
    
    // MARK: - Private
    
    // A workflow file carries the module envelope; the config directory's
    // files (policy, schedules) are not workflows and are written as they are.
    private func writeWorkflow(_ body: String, named name: String, in directory: URL) throws {
        try write(workflowFile(body), named: name, in: directory)
    }

    private func write(_ body: String, named name: String, in directory: URL) throws {
        try body.write(to: directory.appendingPathComponent("\(name).yaml"),
            atomically: true, encoding: .utf8)
    }
    
    private func assertAccountedForExactlyOnce(
        _ snapshot: WorkflowCatalog.Snapshot, in directory: URL,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let onDisk = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { name in name.hasSuffix(".yaml") })
        let live = snapshot.entries.map(\.path)
        let broken = snapshot.failures.map(\.path)
        #expect(Set(live).intersection(broken) == [], "counted on both sides at once")
        #expect(Set(live).union(broken) == onDisk, "missing from the accounting — evaporated from the response")
    }
}
