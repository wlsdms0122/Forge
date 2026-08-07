//
//  ResourceStoreTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("ResourceStore Tests")
struct ResourceStoreTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("resource")
    // MARK: - Initializer
    // MARK: - Test
    @Test("read and list share one membership rule — what is visible and what is readable never diverge")
    func readAndListShareOneMembershipRule() async throws {
        // Given
        let base = try makeBase(); defer { try? FileManager.default.removeItem(at: base) }
        try "visible".write(to: base.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: base.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        try "shadow".write(to: base.appendingPathComponent(".hidden/x.md"),
            atomically: true, encoding: .utf8)
        try "dot".write(to: base.appendingPathComponent(".DS_Store"),
            atomically: true, encoding: .utf8)
        let store = ResourceStore(directory: base)

        // When
        let listed = await store.all().map(\.path)

        // Then
        #expect(listed == ["a.md"])
        let content = try await store.read("a.md")
        #expect(content == "visible")
        do {
            _ = try await store.read(".hidden/x.md")
            Issue.record("a hidden component must be refused by read too (same predicate as list)")
        } catch { #expect("\(error)".contains("hidden"), "\(error)") }
    }
    
    @Test("Path escape is rejected in escape vocabulary")
    func traversalKeepsEscapeVocabulary() async throws {
        // Given
        let base = try makeBase(); defer { try? FileManager.default.removeItem(at: base) }
        let store = ResourceStore(directory: base)
        do {

        // When
            _ = try await store.read("../../etc/hosts")

        // Then
            Issue.record("an escaping path must be refused")
        } catch {
            #expect("\(error)".contains("escapes"), "`..` is an escape, not hiding — must be refused in escape vocabulary: \(error)")
        }
    }
    
    @Test("A symlink pointing inside the base is open to both list and read")
    func symlinkLeafInsideBaseIsListedAndReadable() async throws {
        // Given
        let base = try makeBase(); defer { try? FileManager.default.removeItem(at: base) }
        try "real".write(to: base.appendingPathComponent("real.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: base.appendingPathComponent("link.md"),
            withDestinationURL: base.appendingPathComponent("real.md"))
        let store = ResourceStore(directory: base)

        // When
        let listed = await store.all().map(\.path)

        // Then
        #expect(listed.contains("link.md"), "a symlink leaf pointing inside base is readable, so it must appear in list too: \(listed)")
        let content = try await store.read("link.md")
        #expect(content == "real")
    }
    
    // MARK: - Private
    private func makeBase() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("forge-res-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        return directory
    }
}
