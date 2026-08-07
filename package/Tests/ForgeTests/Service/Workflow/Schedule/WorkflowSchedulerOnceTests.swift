//
//  WorkflowSchedulerOnceTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
import Yams
@testable import Forge

/// once schedules — whether they stay or are removed after a single fire, and the outcome on resolution failure.
@Suite("WorkflowSchedulerOnce Tests", .exclusive(.logSink), .exclusive(.standardError))
struct WorkflowSchedulerOnceTests {
    // MARK: - Property
    private let fixture = SchedulerFixture("scheduler-once")

    // MARK: - Initializer
    // MARK: - Test
    @Test("A once that fails resolution is retained with a denied outcome — never GCed")
    func onceResolveFailureIsRetainedWithDeniedOutcome() async throws {
        // Given
        let directory = try fixture.temporary.make("once-den")
        let rtDir = try fixture.temporary.make("once-den-rt")
        let marker = try fixture.temporary.make("once-den-m").appendingPathComponent("m")
        let badID = ScheduleIDSpace.stamp("bad")
        let (scheduler, ledger, onceFile) = try fixture.onceScheduler(
            onceYAML: "id: \(badID)\nworkflow: nope\nonce: \"2020-01-01 00:00:00\"\ntimezone: Asia/Seoul\n",
            onceFileName: "\(badID).yaml",
            configDir: directory, runtimeDirectory: rtDir, marker: marker, runtimeOwned: true)
        let records = try await LogSinkCapture.capture("sched-once-denied") { capture in
            await scheduler.tickOnce()
            try await Task.sleep(for: .milliseconds(200))
            await scheduler.tickOnce()

            return capture.records(kind: "schedule.denied")
        }

        // Then
        #expect(
            records.contains { record in record.payload["schedule_id"] == .string(badID) },
            "even a once that fails resolution must leave a denied trace")
        #expect(fixture.read(marker) == "", "the workflow must not run")
        #expect(FileManager.default.fileExists(atPath: onceFile.path), "a once exhausted as denied is not GCed — it must stay visible on the surface (list flag)")
        let record = await ledger.snapshot()[badID]
        #expect(record?.state == .closed(.denied(reason: "workflow_missing")), "the ledger outcome must remain denied(reason)")
        #expect(fixture.read(marker) == "", "must not re-fire (the slot is exhausted)")
    }

    @Test("A runtime-owned once cleans itself up after firing")
    func onceRuntimeFiresThenAutoGCs() async throws {
        // Given
        let directory = try fixture.temporary.make("once-rt")
        let rtDir = try fixture.temporary.make("once-rt-dir")
        let marker = try fixture.temporary.make("once-rt-m").appendingPathComponent("m")
        let rtID = ScheduleIDSpace.stamp("one")
        let (scheduler, ledger, onceFile) = try fixture.onceScheduler(
            onceYAML: "id: \(rtID)\nworkflow: wfonce\nonce: \"2020-01-01 00:00:00\"\ntimezone: Asia/Seoul\n",
            onceFileName: "\(rtID).yaml",
            configDir: directory, runtimeDirectory: rtDir, marker: marker, runtimeOwned: true)

        // When
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(400))

        // Then
        #expect(fixture.read(marker) == "1", "the once must fire exactly once")
        #expect(FileManager.default.fileExists(atPath: onceFile.path), "the file must still exist right after firing (self-delete abandoned)")
        let fired = await ledger.lastAttempt(id: rtID)
        #expect(fired != nil, "the fire state must be recorded in the ledger")
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!FileManager.default.fileExists(atPath: onceFile.path), "the daemon must auto-GC a runtime-owned exhausted once")
        #expect(fixture.read(marker) == "1", "must not re-fire")
        let cleared = await ledger.lastAttempt(id: rtID)
        #expect(cleared == nil, "the ledger entry must be cleaned up with the GC")
    }

    @Test("A config-owned once remains after firing")
    func onceConfigStaysAfterFire() async throws {
        // Given
        let configDir = try fixture.temporary.make("once-cfg")
        let runtimeDirectory = try fixture.temporary.make("once-cfg-rt")
        let marker = try fixture.temporary.make("once-cfg-m").appendingPathComponent("m")
        let (scheduler, ledger, onceFile) = try fixture.onceScheduler(
            onceYAML: "id: cfg\nworkflow: wfonce\nonce: \"2020-01-01 00:00:00\"\ntimezone: Asia/Seoul\n",
            onceFileName: "cfg.yaml",
            configDir: configDir, runtimeDirectory: runtimeDirectory, marker: marker)

        // When
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(400))
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(300))

        // Then
        #expect(FileManager.default.fileExists(atPath: onceFile.path), "the daemon must not delete a config-owned exhausted once")
        #expect(fixture.read(marker) == "1", "a config once also fires exactly once")
        let fired = await ledger.lastAttempt(id: "cfg")
        #expect(fired != nil, "a config once's fire state must persist in the ledger to prevent re-firing")
    }

    @Test("A recurring schedule's resolution failure is observed as a denied event")
    func recurringResolveFailureEmitsDeniedEvent() async throws {
        // Given
        let scheduler = try fixture.scheduler(
            workflows: [],
            scheduleYAML: ["ghost": "id: ghost\nworkflow: nope\nevery: 1s\n"])
        let records = try await LogSinkCapture.capture("sched-denied") { capture in
            await scheduler.tickOnce()
            try await Task.sleep(for: .milliseconds(1_100))
            await scheduler.tickOnce()

            return capture.records()
        }
        let denied = records.filter { record in
            record.kind == "schedule.denied" && record.payload["schedule_id"] == .string("ghost")
        }

        // Then
        #expect(!denied.isEmpty, "a resolution failure must be observed as schedule.denied")
        #expect(
            denied.contains { record in record.payload["reason"] == .string("workflow_missing") },
            "denied must carry a machine-readable reason code")
        #expect(
            !records.contains { record in
                record.kind == "schedule.fired" && record.payload["schedule_id"] == .string("ghost")
            },
            "a fire that failed resolution must not be recorded as fired")
    }

    // MARK: - Private
}
