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
        #expect(snapshot.failures.map(\.name) == ["mender"])
        try writeWorkflow(validBody, named: "mender", in: directory)
        snapshot = await catalog.reload()
        try assertAccountedForExactlyOnce(snapshot, in: directory)
        #expect(snapshot.entries.map(\.workflow.name) == ["mender"])
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
        #expect(snapshot.entries.map(\.workflow.name) == ["ok"])
        #expect(snapshot.failures.compactMap(\.name) == ["bad"])
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
        #expect(snapshot.entries.map(\.workflow.name) == ["ok"])
        #expect(snapshot.failures.compactMap(\.name) == ["unbuilt"])
        #expect(snapshot.failures.first?.reason.hasPrefix("build: 4:5: ") == true)

        guard case .invalid = await sut.resolve("unbuilt") else {
            Issue.record("a workflow that does not build resolves as broken")
            return
        }

        _ = try await Builder().build(await sut.modules() + ForgeVocabulary.shipped.get().linkables)
    }

    @Test("Workflows lean on each other: one calls another by its short name and its arguments by name")
    func workflowsLeanOnEachOther() async throws {
        // Given
        let directory = try temporary.make("wf-leaning")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeWorkflow("""
        returns: Int
        result: { call: { procedure: scaled, arguments: { base: 21 } } }
        """, named: "caller", in: directory)
        try writeWorkflow("""
        parameters: [ base: Int, by: { type: Int, default: 2 } ]
        returns: Int
        result: { of: { ref: base }, times: { ref: by } }
        """, named: "scaled", in: directory)
        let sut = try WorkflowCatalog(directory: directory)

        // When
        let snapshot = await sut.reload()

        // Then
        #expect(snapshot.failures.isEmpty)
        #expect(snapshot.entries.map(\.workflow.name) == ["caller", "scaled"])

        let image = try await Builder().build(await sut.modules() + ForgeVocabulary.shipped.get().linkables)
        let answer = try await Executor().run(image, entry: try Name("caller"), arguments: [:])

        #expect(answer == .int(42))
    }

    @Test("A workflow named by a short name the library or std gives is refused at its own file, and the files writing that name build")
    func aWorkflowNamedLikeTheVocabularyIsRefusedAlone() async throws {
        // Given
        let directory = try temporary.make("wf-named")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeWorkflow("""
        returns: String
        result: hello
        """, named: "run", in: directory)
        try writeWorkflow("""
        returns: Int
        result: 0
        """, named: "count", in: directory)
        try writeWorkflow("""
        returns: Forge.Run
        result: { call: { procedure: run } }
        """, named: "who", in: directory)
        try writeWorkflow("""
        returns: Int
        result: { call: { procedure: count, arguments: [ [1, 2, 3] ] } }
        """, named: "sized", in: directory)
        let sut = try WorkflowCatalog(directory: directory)

        // When
        let snapshot = await sut.reload()

        // Then
        try assertAccountedForExactlyOnce(snapshot, in: directory)
        #expect(snapshot.entries.map(\.workflow.name) == ["sized", "who"])
        #expect(snapshot.failures.compactMap(\.name) == ["count", "run"])
        #expect(snapshot.failures.allSatisfy { failure in failure.reason.hasPrefix("a workflow is called by its name") })
        #expect(snapshot.failures.last?.reason.contains("'run' is the short name of Forge.run") == true)
    }

    @Test("A workflow named by a key the notation spells is refused at its own file, and the files writing that key read it as the notation does")
    func aWorkflowNamedLikeAnOperatorIsRefusedAlone() async throws {
        // Given
        let directory = try temporary.make("wf-operator")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeWorkflow("""
        parameters: [ of: Int, to: Int ]
        returns: Bool
        result: true
        """, named: "is", in: directory)
        try writeWorkflow("""
        returns: Bool
        result: { of: 1, is: 2 }
        """, named: "same", in: directory)
        let sut = try WorkflowCatalog(directory: directory)

        // When
        let snapshot = await sut.reload()

        // Then
        #expect(snapshot.entries.map(\.workflow.name) == ["same"])
        #expect(snapshot.failures.compactMap(\.name) == ["is"])

        let image = try await Builder().build(await sut.modules() + ForgeVocabulary.shipped.get().linkables)
        let answer = try await Executor().run(image, entry: try Name("same"), arguments: [:])

        #expect(answer == .bool(false))
    }

    @Test("A file nested deeper than the cooperative pool's stack holds is refused at its line")
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
        #expect(snapshot.entries.map(\.workflow.name) == ["ok"])
        #expect(snapshot.failures.compactMap(\.name) == ["deep"])
        #expect(snapshot.failures.first?.reason.hasSuffix("the text nests deeper than 128 containers") == true)
    }

    @Test("An inline spec nested deeper than the cooperative pool's stack holds is refused")
    func aDeeplyNestedInlineSpecIsRefused() async throws {
        // Given
        let sut = try WorkflowCatalog(directory: nil)
        let result = (0..<400).reduce(JSONValue.int(1)) { nested, _ in .array([nested]) }

        do {

        // When
            _ = try await sut.inline(.object(["returns": "Any", "result": result]))

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
        #expect(snapshot.entries.map(\.workflow.name) == ["visible"])
        #expect(snapshot.failures.contains { failure in failure.path == "<scan>" }, "the blocked enumeration never made it into the same response")
    }
    
    // MARK: - ScheduleStore
    @Test("The schedule snapshot is one observation — no mix of fragmented moments")
    func scheduleCatalogIsOneObservation() async throws {
        // Given
        let config = try temporary.make("sched-config")
        defer { try? FileManager.default.removeItem(at: config) }
        try write("workflow: w\nevery: 1h\n", named: "good", in: config)
        try write("steps: notalist\n", named: "bad", in: config)
        let store = ScheduleStore(configDir: config,
            stateFile: config.appendingPathComponent("state.json"))

        // When
        let snapshot = await store.reload()

        // Then
        #expect(snapshot.entries.map(\.schedule.id) == ["good"])
        #expect(snapshot.failures.map(\.path) == ["bad.yaml"])
    }
    
    @Test("A schedule directory the scan could not enter is a failure at <scan>")
    func scheduleScanObstructionIsReported() async throws {
        // Given
        let config = try temporary.make("sched-obstruction")
        let closed = config.appendingPathComponent("closed")
        try FileManager.default.createDirectory(at: closed, withIntermediateDirectories: true)
        try write("workflow: w\nevery: 1h\n", named: "visible", in: config)
        try write("workflow: w\nevery: 1h\n", named: "hidden", in: closed)
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
            ofItemAtPath: closed.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                ofItemAtPath: closed.path)
            try? FileManager.default.removeItem(at: config)
        }
        let store = ScheduleStore(configDir: config,
            stateFile: config.appendingPathComponent("state.json"))

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
        try write(workflowFile(body, named: name), named: name, in: directory)
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
            .filter { name in name.hasSuffix(".yaml") }
            .map { name in (name as NSString).deletingPathExtension })
        let live = snapshot.entries.map(\.workflow.name)
        let broken = snapshot.failures.compactMap(\.name)
        #expect(Set(live).intersection(broken) == [], "counted on both sides at once")
        #expect(Set(live).union(broken) == onDisk, "missing from the accounting — evaporated from the response")
    }
}
