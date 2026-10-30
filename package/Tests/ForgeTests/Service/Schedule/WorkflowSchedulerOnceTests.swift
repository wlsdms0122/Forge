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

// once schedules: whether they stay or are removed after a single fire, and the outcome on resolution failure.
@Suite("WorkflowSchedulerOnce Tests", .exclusive(.logSink), .exclusive(.standardError))
struct WorkflowSchedulerOnceTests {
    // MARK: - Property
    private let fixture = SchedulerFixture("scheduler-once")

    // MARK: - Initializer
    // MARK: - Test
    @Test("A once that fails resolution is retained with a denied outcome, never collected")
    func onceResolveFailureIsRetainedWithDeniedOutcome() async throws {
        // Given
        let directory = try fixture.temporary.make("once-den")
        let marker = try fixture.temporary.make("once-den-m").appendingPathComponent("m")
        let (sut, ledger, onceFile) = try await fixture.onceScheduler(
            onceYAML: "id: bad\nworkflow: nope\nonce: \"2020-01-01 00:00:00\"\ntimezone: Asia/Seoul\n",
            onceFileName: "bad.yaml",
            directory: directory, marker: marker)

        // When
        let records = try await LogSinkCapture.capture("sched-once-denied") { capture in
            await sut.tickOnce()
            try await Task.sleep(for: .milliseconds(200))
            await sut.tickOnce()

            return capture.records(kind: "schedule.denied")
        }

        // Then
        #expect(
            records.contains { record in record.payload["schedule_id"] == .string("bad") },
            "even a once that fails resolution must leave a denied trace")
        #expect(fixture.read(marker) == "", "the workflow must not run")
        #expect(FileManager.default.fileExists(atPath: onceFile.path), "a once exhausted as denied is not collected; it must stay visible on the surface (list flag)")
        let record = await ledger.snapshot()["bad"]
        #expect(record?.state == .closed(.denied(reason: "workflow_missing")), "the ledger outcome must remain denied(reason)")
        #expect(fixture.read(marker) == "", "must not re-fire (the slot is exhausted)")
    }

    @Test("A spent once written as a file is collected after firing")
    func writtenOnceFiresThenIsCollected() async throws {
        // Given
        let directory = try fixture.temporary.make("once-file")
        let marker = try fixture.temporary.make("once-file-m").appendingPathComponent("m")
        let (sut, ledger, onceFile) = try await fixture.onceScheduler(
            onceYAML: "id: one\nworkflow: wfonce.yaml\nonce: \"2020-01-01 00:00:00\"\ntimezone: Asia/Seoul\n",
            onceFileName: "one.yaml",
            directory: directory, marker: marker)

        // When
        await sut.tickOnce()
        try await Task.sleep(for: .milliseconds(400))
        let fileAfterFire = FileManager.default.fileExists(atPath: onceFile.path)
        let fired = await ledger.lastAttempt(id: "one")
        await sut.tickOnce()
        try await Task.sleep(for: .milliseconds(300))

        // Then
        #expect(fileAfterFire, "the file stays right after firing; the next tick collects it")
        #expect(fired != nil, "the fire state must be recorded in the ledger")
        #expect(!FileManager.default.fileExists(atPath: onceFile.path), "the daemon must collect a spent once")
        #expect(fixture.read(marker) == "1", "the once must fire exactly once")
        let cleared = await ledger.lastAttempt(id: "one")
        #expect(cleared == nil, "the ledger entry must be cleaned up with the collection")
    }

    @Test("A spent once created through the store is collected after firing")
    func createdOnceFiresThenIsCollected() async throws {
        // Given
        let directory = try fixture.temporary.make("once-made")
        let marker = try fixture.temporary.make("once-made-m").appendingPathComponent("m")
        let (sut, ledger, store) = try await fixture.onceStage(directory: directory, marker: marker)
        let created = try await store.create(Schedule(
            id: "made",
            workflow: "wfonce.yaml",
            trigger: .once(fireAt: Date(timeIntervalSince1970: 1_577_804_400), timezone: .seoul)))
        let onceFile = directory.appendingPathComponent("\(created.id).yaml")

        // When
        await sut.tickOnce()
        try await Task.sleep(for: .milliseconds(400))
        let fired = await ledger.lastAttempt(id: "made")
        await sut.tickOnce()
        try await Task.sleep(for: .milliseconds(300))

        // Then
        #expect(fired != nil, "the fire state must be recorded in the ledger")
        #expect(!FileManager.default.fileExists(atPath: onceFile.path), "the daemon must collect a spent once")
        let gone = await store.lookup("made")
        #expect(gone == nil, "a collected once is gone from the store")
        #expect(fixture.read(marker) == "1", "the once must fire exactly once")
        let cleared = await ledger.lastAttempt(id: "made")
        #expect(cleared == nil, "the ledger entry must be cleaned up with the collection")
    }

    @Test("A recurring schedule's resolution failure is observed as a denied event")
    func recurringResolveFailureEmitsDeniedEvent() async throws {
        // Given
        let scheduler = try await fixture.scheduler(
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
