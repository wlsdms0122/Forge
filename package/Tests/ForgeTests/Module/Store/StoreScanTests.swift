//
//  StoreScanTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/25/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("StoreScan Tests")
struct StoreScanTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("scan")

    // MARK: - Initializer
    // MARK: - Test
    @Test("A file whose metadata cannot be read obstructs the scan at that file")
    func unreadableMetadataIsAnObstruction() {
        // Given
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("storescan-\(UUID().uuidString)")
            .appendingPathComponent("gone.yaml")
        var sut = StoreScan(files: [ScannedFile(url: missing, source: "gone.yaml")])

        // When
        let observed = sut.observe()

        // Then
        #expect(observed.isEmpty)
        #expect(sut.obstructions.map(\.scope) == ["gone.yaml"])
        #expect(sut.isUnobserved(source: "gone.yaml"))
        #expect(!sut.isUnobserved(source: "other.yaml"))
    }

    @Test("An unreadable subdirectory is reported, not silently skipped")
    func unreadableSubdirectoryIsReportedNotSilentlySkipped() throws {
        // Given
        let directory = try temporary.make("obstruction")
        let open = directory.appendingPathComponent("open")
        let closed = directory.appendingPathComponent("closed")
        for sub in [open, closed] {
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        }
        try writeFile(named: "visible", in: open)
        try writeFile(named: "hidden", in: closed)
        try chmod(closed, 0o000)
        defer {
            try? chmod(closed, 0o755)
            try? FileManager.default.removeItem(at: directory)
        }
        
        let scan = StoreScan(directory: directory, pathExtension: StoreScan.specFileExtension)

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
        let scan = StoreScan(directory: directory, pathExtension: StoreScan.specFileExtension)

        // Then
        #expect(scan.obstructions.map(\.scope) == [""])
        #expect(scan.isUnobserved(source: "anything/at/all.yaml"))
    }
    
    @Test("If everything was read, the scan is complete")
    func fullyReadableDirectoryIsComplete() throws {
        // Given
        let directory = try temporary.make("complete")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(named: "a", in: directory)
        let scan = StoreScan(directory: directory, pathExtension: StoreScan.specFileExtension)

        // Then
        #expect(scan.isComplete)
        #expect(scan.files.count == 1)
    }
    
    @Test("A missing directory means 'incomplete', not 'empty'")
    func missingDirectoryIsIncompleteNotEmpty() throws {
        // Given
        let directory = try temporary.make("gone")
        try FileManager.default.removeItem(at: directory)
        let scan = StoreScan(directory: directory, pathExtension: StoreScan.specFileExtension)

        // Then
        #expect(scan.files.isEmpty)
        #expect(!scan.isComplete)
    }

    @Test("An id starting with a dot is not safe")
    func safeIDRejectsLeadingDot() {
        #expect(!StoreScan.isSafeID(".hidden"), "a leading dot makes the file hidden, unreadable on reload, so it is rejected")
        #expect(!StoreScan.isSafeID("."))
        #expect(!StoreScan.isSafeID(".."))
        #expect(!StoreScan.isSafeID(""))
        #expect(StoreScan.isSafeID("v1.2"), "an interior dot is allowed")
        #expect(StoreScan.isSafeID("my-job_1"))
    }

    // MARK: - Public
    // MARK: - Private
    private func writeFile(named name: String, in directory: URL) throws {
        try Data().write(to: directory.appendingPathComponent("\(name).yaml"))
    }

    private func chmod(_ url: URL, _ mode: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }
}
