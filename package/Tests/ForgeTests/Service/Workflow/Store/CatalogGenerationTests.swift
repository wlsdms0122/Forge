//
//  CatalogGenerationTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("CatalogGeneration Tests")
struct CatalogGenerationTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("catalog")

    private let validBody = #"""
    steps:
      - id: x
        shell:
          command: ["/bin/echo", "ok"]
    """#
    
    private let brokenBody = "steps: notalist\n"
    
    // MARK: - Initializer
    // MARK: - Test
    // MARK: - SpecCatalog
    @Test("A repaired definition cannot vanish from the catalog")
    func repairedDefinitionCannotVanishFromTheCatalog() async throws {
        // Given
        let directory = try temporary.make("wf-repair")
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(brokenBody, named: "mender", in: directory)
        let store = SpecCatalog(directory: directory, loader: ForgeSpec.loader())

        // When
        var catalog = await store.catalog()

        // Then
        #expect(catalog.entries.isEmpty)
        #expect(catalog.failures.map(\.name) == ["mender"])
        try write(validBody, named: "mender", in: directory)
        catalog = await store.catalog()
        try assertAccountedForExactlyOnce(catalog, in: directory)
        #expect(catalog.entries.map(\.name) == ["mender"])
        #expect(catalog.failures.isEmpty)
    }
    
    @Test("Live entries and failures do not overlap")
    func catalogEntriesAndFailuresAreDisjoint() async throws {
        // Given
        let directory = try temporary.make("wf-disjoint")
        defer { try? FileManager.default.removeItem(at: directory) }

        // When
        try write(validBody, named: "ok", in: directory)
        try write(brokenBody, named: "bad", in: directory)
        let catalog = await SpecCatalog(directory: directory, loader: ForgeSpec.loader()).catalog()
        try assertAccountedForExactlyOnce(catalog, in: directory)

        // Then
        #expect(catalog.entries.map(\.name) == ["ok"])
        #expect(catalog.failures.compactMap(\.name) == ["bad"])
    }
    
    @Test("A scan obstruction rides in the same observation")
    func scanObstructionRidesTheSameObservation() async throws {
        // Given
        let directory = try temporary.make("wf-obstruction")
        let closed = directory.appendingPathComponent("closed")
        try FileManager.default.createDirectory(at: closed, withIntermediateDirectories: true)
        try write(validBody, named: "visible", in: directory)
        try write(validBody, named: "hidden", in: closed)
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
            ofItemAtPath: closed.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                ofItemAtPath: closed.path)
            try? FileManager.default.removeItem(at: directory)
        }

        // When
        let catalog = await SpecCatalog(directory: directory, loader: ForgeSpec.loader()).catalog()

        // Then
        #expect(catalog.entries.map(\.name) == ["visible"])
        #expect(catalog.failures.contains { failure in failure.path == "<scan>" }, "the blocked enumeration never made it into the same response")
    }
    
    // MARK: - ScheduleStore
    @Test("The schedule catalog is one observation — no mix of fragmented moments")
    func scheduleCatalogIsOneObservation() async throws {
        // Given
        let config = try temporary.make("sched-config")
        defer { try? FileManager.default.removeItem(at: config) }
        try write("workflow: w\nevery: 1h\n", named: "good", in: config)
        try write("steps: notalist\n", named: "bad", in: config)
        let store = ScheduleStore(configDir: config,
            stateFile: config.appendingPathComponent("state.json"))

        // When
        let catalog = await store.catalog()

        // Then
        #expect(catalog.entries.map(\.schedule.id) == ["good"])
        #expect(catalog.failures.map(\.path) == ["bad.yaml"])
    }
    
    // MARK: - PolicyStore
    @Test("The policy catalog is also one observation")
    func policyCatalogIsOneObservation() async throws {
        // Given
        let directory = try temporary.make("policy")
        defer { try? FileManager.default.removeItem(at: directory) }
        try "admin:alice:\n  - \"*\"\n".write(to: directory.appendingPathComponent("ok.yaml"),
            atomically: true, encoding: .utf8)

        // When
        let catalog = await PolicyStore(directory: directory).catalog()

        // Then
        #expect(catalog.policy["admin:alice"] == ["*"])
        #expect(catalog.failures.isEmpty)
    }
    
    // MARK: - Private
    
    private func write(_ body: String, named name: String, in directory: URL) throws {
        try body.write(to: directory.appendingPathComponent("\(name).yaml"),
            atomically: true, encoding: .utf8)
    }
    
    private func assertAccountedForExactlyOnce(
        _ catalog: SpecCatalog.Catalog, in directory: URL,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let onDisk = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { name in name.hasSuffix(".yaml") }
            .map { name in (name as NSString).deletingPathExtension })
        let live = catalog.entries.map(\.name)
        let broken = catalog.failures.compactMap(\.name)
        #expect(Set(live).intersection(broken) == [], "counted on both sides at once")
        #expect(Set(live).union(broken) == onDisk, "missing from the accounting — evaporated from the response")
    }
}
