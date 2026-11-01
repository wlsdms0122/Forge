//
//  WorkflowCatalogScanTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("WorkflowCatalogScan Tests")
struct WorkflowCatalogScanTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("scan")

    // MARK: - Initializer
    // MARK: - Test
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
        
        let catalog = try WorkflowCatalog(directory: directory)
        guard case .found = await catalog.resolve("closed/shadowed.yaml") else {

        // Then
            Issue.record("precondition — before obstructing, both must be visible")
            
            return
        }
        
        try chmod(closed, 0o000)
        guard case .found = await catalog.resolve("closed/shadowed.yaml") else {
            Issue.record("a single enumeration failure erased a deployed definition from the catalog")
            
            return
        }
        
        guard case .found = await catalog.resolve("open/visible.yaml") else {
            Issue.record("an observed definition must be unaffected")
            
            return
        }
        
        switch await catalog.resolve("never-existed.yaml") {
        case .missing:
            Issue.record("absence was claimed despite an incomplete enumeration — dispatch would absorb a deployment defect")
        case .invalid:
            Issue.record("a never-seen definition was claimed 'broken' — a fact that does not exist")
        case .unobserved(let reason):
            #expect(reason.contains("enumerated"), Comment(rawValue: reason))
        case .found:
            Issue.record("a nonexistent name resolved as found")
        }
        
        let failures = await catalog.reload().failures
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
        
        let catalog = try WorkflowCatalog(directory: directory)
        guard case .found = await catalog.resolve("open/deleted-later.yaml") else {

        // Then
            Issue.record("precondition")

            return
        }

        try FileManager.default.removeItem(at: open.appendingPathComponent("deleted-later.yaml"))
        try chmod(closed, 0o000)
        switch await catalog.resolve("open/deleted-later.yaml") {
        case .found:
            Issue.record("a properly observed deletion was resurrected by an unrelated obstruction")
        case .unobserved, .missing, .invalid:
            break
        }
        guard case .found = await catalog.resolve("closed/shadowed.yaml") else {
            Issue.record("a definition inside the observation-failure scope must be carried forward")
            
            return
        }
    }
    
    @Test("Files of one basename in different folders each declare main and each resolve at its own path")
    func filesOfOneBasenameInDifferentFoldersEachResolve() async throws {
        // Given
        let directory = try temporary.make("same-basename")
        defer { try? FileManager.default.removeItem(at: directory) }
        for sub in ["a", "b"] {
            let folder = directory.appendingPathComponent(sub)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try writeWorkflow(named: "dup", in: folder)
        }
        let sut = try WorkflowCatalog(directory: directory)

        // When
        let snapshot = await sut.reload()

        // Then
        #expect(snapshot.entries.map(\.path) == ["a/dup.yaml", "b/dup.yaml"])
        #expect(snapshot.failures.isEmpty)
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
        
        let catalog = try WorkflowCatalog(directory: directory)
        guard case .found = await catalog.resolve("ghost.yaml") else {

        // Then
            Issue.record("precondition")
            
            return
        }
        
        try chmod(directory, 0o444)
        switch await catalog.resolve("ghost.yaml") {
        case .found, .unobserved, .invalid:
            break
        case .missing:
            Issue.record("a definition that became unreadable was folded into absence")
        }
        
        let failures = await catalog.reload().failures
        #expect(!failures.isEmpty, "the observation failure never reached any surface")
    }
    
    @Test("A complete scan still reports genuine absence as absence")
    func completeScanStillReportsGenuineAbsence() async throws {
        // Given
        let directory = try temporary.make("store-complete")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeWorkflow(named: "a", in: directory)
        let catalog = try WorkflowCatalog(directory: directory)
        guard case .missing = await catalog.resolve("nope.yaml") else {

        // Then
            Issue.record("under a complete scan, absence must be .missing")
            
            return
        }
        
        let failures = await catalog.reload().failures
        #expect(failures.isEmpty)
    }
    
    // MARK: - Private
    
    private func writeWorkflow(named name: String, in directory: URL) throws {
        try workflowFile(#"""
        failing: [nonzero_exit, timeout]
        body:
          - let: x
            value: { call: { procedure: shell, arguments: { command: ["/bin/echo", "ok"] } } }
        """#).write(to: directory.appendingPathComponent("\(name).yaml"),
            
            atomically: true, encoding: .utf8)
        
    }
    
    private func chmod(_ url: URL, _ mode: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }
}
