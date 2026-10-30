//
//  ScheduleStoreTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

// The contract for reading schedules from the schedule directory into a snapshot.
@Suite("ScheduleStore Tests")
struct ScheduleStoreTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("schedule-store")

    // MARK: - Initializer
    // MARK: - Test
    // MARK: - load
    @Test("Lookup reads the definition from disk")
    func lookupFromDisk() async throws {
        // Given
        let directory = try temporary.make("lookup")
        defer { try? FileManager.default.removeItem(at: directory) }
        let yaml = #"""
        id: consolidate-hourly
        workflow: consolidate
        every: 1h
        """#
        try yaml.write(to: directory.appendingPathComponent("consolidate-hourly.yaml"),
            atomically: true, encoding: .utf8)
        let store = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let schedule = await store.lookup("consolidate-hourly")

        // Then
        #expect(schedule != nil)
        #expect(schedule?.workflow == "consolidate")
        #expect(schedule?.trigger == .every(Interval(seconds: 3600)))
        #expect(schedule?.concurrency == .queue)
    }

    @Test("A nested file loads under its path without the extension")
    func nestedFileLoadsUnderItsPath() async throws {
        // Given
        let directory = try temporary.make("nested")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("a"), withIntermediateDirectories: true)
        try #"""
        workflow: wf
        every: 1h
        """#.write(to: directory.appendingPathComponent("a/x.yaml"),
            atomically: true, encoding: .utf8)
        let sut = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let schedule = await sut.lookup("a/x")

        // Then
        #expect(schedule?.id == "a/x", "the id is the file's path under the directory")
        #expect(schedule?.workflow == "wf")
        let basename = await sut.lookup("x")
        #expect(basename == nil, "the basename alone does not name a nested schedule")
    }

    @Test("Files with one basename in different directories load under distinct ids")
    func sameBasenameInDifferentDirectoriesLoadsBoth() async throws {
        // Given
        let directory = try temporary.make("same-base")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("a"), withIntermediateDirectories: true)
        try #"""
        workflow: top
        every: 1h
        """#.write(to: directory.appendingPathComponent("x.yaml"),
            atomically: true, encoding: .utf8)
        try #"""
        workflow: nested
        every: 2h
        """#.write(to: directory.appendingPathComponent("a/x.yaml"),
            atomically: true, encoding: .utf8)
        let sut = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let snapshot = await sut.reload()

        // Then
        let byID = Dictionary(uniqueKeysWithValues: snapshot.entries.map { entry in (entry.schedule.id, entry.schedule.workflow) })
        #expect(byID == ["x": "top", "a/x": "nested"], "both files load, each under its own path")
        #expect(snapshot.failures.isEmpty, "distinct paths are distinct ids, so nothing is refused: \(snapshot.failures.map(\.reason))")
    }

    @Test("A nested file whose body id is its basename is refused")
    func nestedFileWithBasenameIDIsRefused() async throws {
        // Given
        let directory = try temporary.make("nested-mismatch")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("a"), withIntermediateDirectories: true)
        try #"""
        id: x
        workflow: wf
        every: 1h
        """#.write(to: directory.appendingPathComponent("a/x.yaml"),
            atomically: true, encoding: .utf8)
        let sut = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let snapshot = await sut.reload()

        // Then
        #expect(snapshot.entries.isEmpty, "a body id that differs from the file's path is refused")
        #expect(
            snapshot.failures.contains { failure in
                failure.path == "a/x.yaml" && failure.reason.contains("must equal the file's path")
            },
            "the refusal surfaces as a failure: \(snapshot.failures.map(\.reason))")
    }

    @Test("When id is omitted it is derived from the filename")
    func iDOmittedDerivesFromFilename() async throws {
        // Given
        let directory = try temporary.make("noid")
        defer { try? FileManager.default.removeItem(at: directory) }
        try #"""
        workflow: consolidate
        every: 1h
        """#.write(to: directory.appendingPathComponent("derived.yaml"),
            atomically: true, encoding: .utf8)
        let store = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let schedule = await store.lookup("derived")

        // Then
        #expect(schedule != nil, "for a file without an id, the filename must be its identity")
        #expect(schedule?.workflow == "consolidate")
    }

    @Test("Loads a wall-clock schedule")
    func wallClockScheduleLoad() async throws {
        // Given
        let directory = try temporary.make("at")
        defer { try? FileManager.default.removeItem(at: directory) }
        try #"""
        id: standup
        workflow: standup
        at: "09:20"
        days: [mon, wed, fri]
        timezone: Asia/Seoul
        """#.write(to: directory.appendingPathComponent("standup.yaml"),
            atomically: true, encoding: .utf8)
        let store = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let schedule = await store.lookup("standup")

        // Then
        #expect(schedule?.trigger == .at(hour: 9, minute: 20, days: [.mon, .wed, .fri], timezone: .seoul))
    }

    @Test("Inputs and the concurrency policy are carried together")
    func inputsAndConcurrencyBound() async throws {
        // Given
        let directory = try temporary.make("inputs")
        defer { try? FileManager.default.removeItem(at: directory) }
        try #"""
        id: quick
        workflow: consolidate
        every: 10m
        concurrency: skip
        inputs:
          scope: quick
          limit: 5
        """#.write(to: directory.appendingPathComponent("quick.yaml"),
            atomically: true, encoding: .utf8)
        let store = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let schedule = await store.lookup("quick")

        // Then
        #expect(schedule?.concurrency == .skip)
        #expect(schedule?.inputs?["scope"] == .string("quick"))
        #expect(schedule?.inputs?["limit"] == .int(5))
    }

    @Test("File edits are picked up on reload")
    func hotReloadPicksUpEdits() async throws {
        // Given
        let directory = try temporary.make("hot")
        defer { try? FileManager.default.removeItem(at: directory) }
        try #"""
        id: s
        workflow: wf
        every: 5m
        """#.write(to: directory.appendingPathComponent("s.yaml"),
            atomically: true, encoding: .utf8)
        let store = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let first = await store.lookup("s")?.trigger

        // Then
        #expect(first == .every(Interval(seconds: 300)))
        try await Task.sleep(for: .seconds(1))
        try #"""
        id: s
        workflow: wf
        every: 1h
        """#.write(to: directory.appendingPathComponent("s.yaml"),
            atomically: true, encoding: .utf8)
        let after = await store.lookup("s")?.trigger
        #expect(after == .every(Interval(seconds: 3600)), "interval must be refreshed")
    }

    // MARK: - serialization round-trip
    @Test("Encoding round-trip holds")
    func encodeRoundTrip() throws {
        // Given
        let cases: [Trigger] = [
            .every(Interval(seconds: 3600)),
            .once(fireAt: Date(timeIntervalSince1970: 1_780_000_000), timezone: .seoul),
            .at(hour: 9, minute: 20, days: [.mon, .fri], timezone: .seoul),
            .at(hour: 0, minute: 5, days: [], timezone: TimeZone(identifier: "UTC")!),
        ]
        for record in cases {
            let schedule = Schedule(id: "b", workflow: "wf", trigger: record)

        // When
            let data = try JSONEncoder().encode(schedule)
            let decoded = try JSONDecoder().decode(Schedule.self, from: data)

        // Then
            #expect(decoded.trigger == record, "round-trip broken: \(record)")
        }
    }
    // MARK: - Private
}
