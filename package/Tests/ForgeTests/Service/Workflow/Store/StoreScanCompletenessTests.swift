//
//  StoreScanCompletenessTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("StoreScanCompleteness Tests")
struct StoreScanCompletenessTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("scan")

    // MARK: - Initializer
    // MARK: - Test
    // MARK: - scanStoreFiles
    @Test("An unreadable subdirectory is reported, not silently skipped")
    func unreadableSubdirectoryIsReportedNotSilentlySkipped() throws {
        // Given
        let directory = try temporary.make("obstruction")
        let open = directory.appendingPathComponent("open")
        let closed = directory.appendingPathComponent("closed")
        for sub in [open, closed] {
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        }
        try writeWorkflow(named: "visible", in: open)
        try writeWorkflow(named: "hidden", in: closed)
        try chmod(closed, 0o000)
        defer {
            try? chmod(closed, 0o755)
            try? FileManager.default.removeItem(at: directory)
        }
        
        let scan = scanStoreFiles(in: directory, pathExtension: specFileExtension)

        // Then
        #expect(scan.files.map(\.source) == ["open/visible.yaml"])
        #expect(!scan.isComplete)
        #expect(scan.obstructions.map(\.scope) == ["closed"])
        #expect(scan.isUnobserved(source: "closed/hidden.yaml"))
        #expect(!scan.isUnobserved(source: "open/visible.yaml"))
        #expect(!scan.isUnobserved(source: "closed-sibling/x.yaml"), "prefix matching that ignores path boundaries swallows unrelated siblings as unobserved")
    }
    
    @Test("When the whole directory is obstructed, that fact covers everything")
    func wholeDirectoryObstructionCoversEverything() throws {
        // Given
        let directory = try temporary.make("gone-scope")
        try FileManager.default.removeItem(at: directory)
        let scan = scanStoreFiles(in: directory, pathExtension: specFileExtension)

        // Then
        #expect(scan.obstructions.map(\.scope) == [""])
        #expect(scan.isUnobserved(source: "anything/at/all.yaml"))
    }
    
    @Test("If everything was read, the scan is complete")
    func fullyReadableDirectoryIsComplete() throws {
        // Given
        let directory = try temporary.make("complete")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeWorkflow(named: "a", in: directory)
        let scan = scanStoreFiles(in: directory, pathExtension: specFileExtension)

        // Then
        #expect(scan.isComplete)
        #expect(scan.files.count == 1)
    }
    
    @Test("A missing directory means 'incomplete', not 'empty'")
    func missingDirectoryIsIncompleteNotEmpty() throws {
        // Given
        let directory = try temporary.make("gone")
        try FileManager.default.removeItem(at: directory)
        let scan = scanStoreFiles(in: directory, pathExtension: specFileExtension)

        // Then
        #expect(scan.files.isEmpty)
        #expect(!scan.isComplete)
    }
    
    // MARK: - SpecCatalog
    @Test("A partial scan neither wipes the cache nor claims absence")
    func partialScanNeitherWipesTheCacheNorClaimsAbsence() async throws {
        // Given
        let directory = try temporary.make("store-partial")
        let open = directory.appendingPathComponent("open")
        let closed = directory.appendingPathComponent("closed")
        for sub in [open, closed] {
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        }
        try writeWorkflow(named: "visible", in: open)
        try writeWorkflow(named: "shadowed", in: closed)
        defer {
            try? chmod(closed, 0o755)
            try? FileManager.default.removeItem(at: directory)
        }
        
        let store = SpecCatalog(directory: directory, loader: ForgeSpec.loader())
        guard case .found = await store.resolve("shadowed") else {

        // Then
            Issue.record("precondition — before obstructing, both must be visible")
            
            return
        }
        
        try chmod(closed, 0o000)
        guard case .found = await store.resolve("shadowed") else {
            Issue.record("a single enumeration failure erased a deployed definition from the catalog")
            
            return
        }
        
        guard case .found = await store.resolve("visible") else {
            Issue.record("an observed definition must be unaffected")
            
            return
        }
        
        switch await store.resolve("never-existed") {
        case .missing:
            Issue.record("absence was claimed despite an incomplete enumeration — dispatch would absorb a deployment defect")
        case .invalid:
            Issue.record("a never-seen definition was claimed 'broken' — a fact that does not exist")
        case .unobserved(let reason):
            #expect(reason.contains("enumerated"), Comment(rawValue: reason))
        case .found:
            Issue.record("a nonexistent name resolved as found")
        }
        
        let failures = await store.catalog().failures
        #expect(failures.contains { failure in failure.reason.contains("scan incomplete") }, "\(failures.map(\.reason))")
    }
    
    @Test("Carry-forward does not resurrect an observed deletion")
    func carryForwardDoesNotResurrectAnObservedDeletion() async throws {
        // Given
        let directory = try temporary.make("store-scope")
        let open = directory.appendingPathComponent("open")
        let closed = directory.appendingPathComponent("closed")
        for sub in [open, closed] {
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        }
        try writeWorkflow(named: "deleted-later", in: open)
        try writeWorkflow(named: "shadowed", in: closed)
        defer {
            try? chmod(closed, 0o755)
            try? FileManager.default.removeItem(at: directory)
        }
        
        let store = SpecCatalog(directory: directory, loader: ForgeSpec.loader())
        guard case .found = await store.resolve("deleted-later") else {

        // Then
            Issue.record("precondition")

            return
        }

        try FileManager.default.removeItem(at: open.appendingPathComponent("deleted-later.yaml"))
        try chmod(closed, 0o000)
        switch await store.resolve("deleted-later") {
        case .found:
            Issue.record("a properly observed deletion was resurrected by an unrelated obstruction")
        case .unobserved, .missing, .invalid:
            break
        }
        guard case .found = await store.resolve("shadowed") else {
            Issue.record("a definition inside the observation-failure scope must be carried forward")
            
            return
        }
    }
    
    @Test("A name collision does not resolve itself just because there was an obstruction")
    func collisionSurvivesAnObstructionInsteadOfResolvingItself() async throws {
        // Given
        let directory = try temporary.make("collision-obstructed")
        let firstDirectory = directory.appendingPathComponent("a")
        let secondDirectory = directory.appendingPathComponent("b")
        for sub in [firstDirectory, secondDirectory] {
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        }
        try writeWorkflow(named: "dup", in: firstDirectory)
        try writeWorkflow(named: "dup", in: secondDirectory)
        defer {
            try? chmod(secondDirectory, 0o755)
            try? FileManager.default.removeItem(at: directory)
        }
        
        let store = SpecCatalog(directory: directory, loader: ForgeSpec.loader())
        guard case .invalid = await store.resolve("dup") else {

        // Then
            Issue.record("precondition — a collision must exclude both sides from live")
            
            return
        }
        
        try chmod(secondDirectory, 0o000)
        switch await store.resolve("dup") {
        case .found:
            Issue.record("while the shadowed collision partner was invisible, the remaining side became runnable")
        case .invalid, .unobserved, .missing:
            break
        }
    }
    
    @Test("An unreadable definition is never folded into absence")
    func unreadableDefinitionIsNeverFoldedIntoAbsence() async throws {
        // Given
        let directory = try temporary.make("meta")
        try writeWorkflow(named: "ghost", in: directory)
        defer {
            try? chmod(directory, 0o755)
            try? FileManager.default.removeItem(at: directory)
        }
        
        let store = SpecCatalog(directory: directory, loader: ForgeSpec.loader())
        guard case .found = await store.resolve("ghost") else {

        // Then
            Issue.record("precondition")
            
            return
        }
        
        try chmod(directory, 0o444)
        switch await store.resolve("ghost") {
        case .found, .unobserved, .invalid:
            break
        case .missing:
            Issue.record("a definition that became unreadable was folded into absence")
        }
        
        let failures = await store.catalog().failures
        #expect(!failures.isEmpty, "the observation failure never reached any surface")
    }
    
    @Test("A complete scan still reports genuine absence as absence")
    func completeScanStillReportsGenuineAbsence() async throws {
        // Given
        let directory = try temporary.make("store-complete")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeWorkflow(named: "a", in: directory)
        let store = SpecCatalog(directory: directory, loader: ForgeSpec.loader())
        guard case .missing = await store.resolve("nope") else {

        // Then
            Issue.record("under a complete scan, absence must be .missing")
            
            return
        }
        
        let failures = await store.catalog().failures
        #expect(failures.isEmpty)
    }
    
    // MARK: - Private
    
    private func writeWorkflow(named name: String, in directory: URL) throws {
        try #"""
        steps:
          - id: x
            shell:
              command: ["/bin/echo", "ok"]
        """#.write(to: directory.appendingPathComponent("\(name).yaml"),
            
            atomically: true, encoding: .utf8)
        
    }
    
    private func chmod(_ url: URL, _ mode: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }
}
