//
//  ScheduleStoreTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

/// The contract for reading schedules from the config directory and building the catalog.
@Suite("ScheduleStore Tests")
struct ScheduleStoreTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("schedule-store")

    // MARK: - Initializer
    // MARK: - Test
    // MARK: - config load
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
        let store = ScheduleStore(configDir: directory, stateFile: try temporary.file("schedule-enabled.json"))

        // When
        let schedule = await store.lookup("consolidate-hourly")

        // Then
        #expect(schedule != nil)
        #expect(schedule?.workflow == "consolidate")
        #expect(schedule?.trigger == .every(Interval(seconds: 3600)))
        #expect(schedule?.concurrency == .queue)
    }

    @Test("Runtime and config have distinct id spaces and cannot collide")
    func runtimeAndConfigIdSpacesCannotCollide() async throws {
        // Given
        let configDir = try temporary.make("ns-cfg")
        let runtimeDirectory = try temporary.make("ns-rt")
        defer {
            try? FileManager.default.removeItem(at: configDir)
            try? FileManager.default.removeItem(at: runtimeDirectory)
        }
        try #"""
        id: rt.squat
        workflow: a
        every: 1h
        """#.write(to: configDir.appendingPathComponent("rt.squat.yaml"),
            atomically: true, encoding: .utf8)
        try #"""
        id: plain
        workflow: b
        every: 2h
        """#.write(to: runtimeDirectory.appendingPathComponent("plain.yaml"),
            atomically: true, encoding: .utf8)
        let store = ScheduleStore(configDir: configDir, runtimeDirectory: runtimeDirectory,
            stateFile: try temporary.file("schedule-enabled.json"))

        // When
        let squat = await store.lookup("rt.squat")

        // Then
        #expect(squat == nil, "config may not use the runtime partition prefix")
        let plain = await store.lookup("plain")
        #expect(plain == nil, "a runtime declaration cannot live without the partition stamp")
        let failures = await store.catalog().failures
        #expect(failures.filter { failure in failure.reason.contains("rename this config declaration") }.count == 1, "\(failures.map(\.reason))")
        #expect(failures.filter { failure in failure.reason.contains("must start with") }.count == 1, "\(failures.map(\.reason))")
    }

    @Test("A collision within the same space excludes both sides")
    func sameSpaceCollisionStillExcludesBoth() async throws {
        // Given
        let configDir = try temporary.make("col-cfg")
        defer { try? FileManager.default.removeItem(at: configDir) }
        for sub in ["a", "b"] {
            try FileManager.default.createDirectory(
                at: configDir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        try #"""
        id: dup
        workflow: a
        every: 1h
        """#.write(to: configDir.appendingPathComponent("a/dup.yaml"),
            atomically: true, encoding: .utf8)
        try #"""
        id: dup
        workflow: b
        every: 2h
        """#.write(to: configDir.appendingPathComponent("b/dup.yaml"),
            atomically: true, encoding: .utf8)
        let store = ScheduleStore(configDir: configDir, runtimeDirectory: nil, stateFile: try temporary.file("schedule-enabled.json"))

        // When
        let schedule = await store.lookup("dup")

        // Then
        #expect(schedule == nil, "same id in the same partition = collision, exclude both")
        let all = await store.catalog().entries.map(\.schedule)
        #expect(!all.contains { entry in entry.id == "dup" })
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
        let store = ScheduleStore(configDir: directory, stateFile: try temporary.file("schedule-enabled.json"))

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
        let store = ScheduleStore(configDir: directory, stateFile: try temporary.file("schedule-enabled.json"))

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
        let store = ScheduleStore(configDir: directory, stateFile: try temporary.file("schedule-enabled.json"))

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
        let store = ScheduleStore(configDir: directory, stateFile: try temporary.file("schedule-enabled.json"))

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
