//
//  WorkingDirectoryTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("WorkingDirectory Tests")
struct WorkingDirectoryTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("resource")
    // MARK: - Initializer
    // MARK: - Test
    @Test("readInside and all share one rule, so what is listed is what is read")
    func readInsideAndAllShareOneRule() async throws {
        // Given
        let base = try makeBase(); defer { try? FileManager.default.removeItem(at: base) }
        try write("visible", to: "a.md", in: base)
        try write("shadow", to: ".hidden/x.md", in: base)
        try write("dot", to: ".DS_Store", in: base)
        let sut = WorkingDirectory(directory: base)

        // When
        let listed = await sut.all().map(\.path)
        let refusal = await #expect(throws: ResourceError.self) {
            try await sut.readInside(".hidden/x.md")
        }

        // Then
        #expect(listed == ["a.md"])
        #expect(try await sut.readInside("a.md") == "visible")
        #expect(refusal?.message.contains("hidden component") == true)
    }

    @Test("read takes a path as a shell does: absolute as written, relative under the directory, hidden parts too")
    func readResolvesAsWritten() async throws {
        // Given
        let base = try makeBase(); defer { try? FileManager.default.removeItem(at: base) }
        let outside = try makeBase(); defer { try? FileManager.default.removeItem(at: outside) }
        try write("shadow", to: ".hidden/x.md", in: base)
        try write("elsewhere", to: "y.md", in: outside)
        let sut = WorkingDirectory(directory: base)

        // When
        let hidden = try await sut.read(".hidden/x.md")
        let absolute = try await sut.read(outside.appendingPathComponent("y.md").path)

        // Then
        #expect(hidden == "shadow")
        #expect(absolute == "elsewhere")
    }

    @Test("readInside refuses an absolute path, even one under the directory")
    func readInsideRefusesAnAbsolutePath() async throws {
        // Given
        let base = try makeBase(); defer { try? FileManager.default.removeItem(at: base) }
        try write("visible", to: "a.md", in: base)
        let sut = WorkingDirectory(directory: base)

        // When
        let refusal = await #expect(throws: ResourceError.self) {
            try await sut.readInside(base.appendingPathComponent("a.md").path)
        }

        // Then
        #expect(refusal?.message.contains("is absolute") == true)
    }

    @Test("A path with a '..' part is refused by read and readInside", arguments: ["../x.md", "a/../a.md"])
    func aClimbingPathIsRefused(path: String) async throws {
        // Given
        let base = try makeBase(); defer { try? FileManager.default.removeItem(at: base) }
        try write("visible", to: "a.md", in: base)
        let sut = WorkingDirectory(directory: base)

        // When
        let read = await #expect(throws: ResourceError.self) { try await sut.read(path) }
        let inside = await #expect(throws: ResourceError.self) { try await sut.readInside(path) }

        // Then
        #expect(read?.message.contains("'..' part") == true)
        #expect(inside?.message.contains("'..' part") == true)
    }

    @Test("A symlink pointing inside the directory is listed and read")
    func symlinkInsideIsListedAndRead() async throws {
        // Given
        let base = try makeBase(); defer { try? FileManager.default.removeItem(at: base) }
        try write("real", to: "real.md", in: base)
        try FileManager.default.createSymbolicLink(
            at: base.appendingPathComponent("link.md"),
            withDestinationURL: base.appendingPathComponent("real.md")
        )
        let sut = WorkingDirectory(directory: base)

        // When
        let listed = await sut.all().map(\.path)

        // Then
        #expect(listed.contains("link.md"))
        #expect(try await sut.readInside("link.md") == "real")
    }

    @Test("A symlink leading out of the directory is not listed and refused by readInside")
    func symlinkOutIsRefusedInside() async throws {
        // Given
        let base = try makeBase(); defer { try? FileManager.default.removeItem(at: base) }
        let outside = try makeBase(); defer { try? FileManager.default.removeItem(at: outside) }
        try write("elsewhere", to: "y.md", in: outside)
        try FileManager.default.createSymbolicLink(
            at: base.appendingPathComponent("link.md"),
            withDestinationURL: outside.appendingPathComponent("y.md")
        )
        let sut = WorkingDirectory(directory: base)

        // When
        let listed = await sut.all().map(\.path)
        let refusal = await #expect(throws: ResourceError.self) {
            try await sut.readInside("link.md")
        }

        // Then
        #expect(listed.isEmpty)
        #expect(refusal?.message.contains("outside the working directory") == true)
    }

    // MARK: - Private
    private func makeBase() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("forge-res-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        return directory
    }

    private func write(_ text: String, to path: String, in base: URL) throws {
        let url = base.appendingPathComponent(path)

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
