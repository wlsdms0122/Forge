//
//  StoreObservationTests.swift
//  ForgeTests
//
//  Created by JSilver on 11/1/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("StoreObservation Tests")
struct StoreObservationTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("observation")

    // MARK: - Initializer
    // MARK: - Test
    // MARK: - ScheduleStore
    @Test("The schedule snapshot is one observation, no mix of fragmented moments")
    func scheduleSnapshotIsOneObservation() async throws {
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
        #expect(snapshot.failures.first?.reason.hasPrefix("schedule directory scan incomplete") == true)
        #expect(snapshot.failures.first?.reason.contains("closed") == true)
    }

    // MARK: - PolicyStore
    @Test("The policy snapshot is also one observation")
    func policySnapshotIsOneObservation() async throws {
        // Given
        let directory = try temporary.make("policy")
        defer { try? FileManager.default.removeItem(at: directory) }
        try write("admin:alice:\n  - \"*\"\n", named: "ok", in: directory)

        // When
        let snapshot = await PolicyStore(directory: directory).reload()

        // Then
        #expect(snapshot.policy["admin:alice"] == ["*"])
        #expect(snapshot.failures.isEmpty)
    }

    // MARK: - Public
    // MARK: - Private
    private func write(_ body: String, named name: String, in directory: URL) throws {
        try body.write(to: directory.appendingPathComponent("\(name).yaml"),
            atomically: true, encoding: .utf8)
    }
}
