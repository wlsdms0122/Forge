//
//  WorkflowSchedulerLedgerTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

/// Fire ledger — records slot outcomes, blocks divergence when persist fails, recovers from corruption.
@Suite("WorkflowSchedulerLedger Tests", .exclusive(.logSink), .exclusive(.standardError))
struct WorkflowSchedulerLedgerTests {
    // MARK: - Property
    private let fixture = SchedulerFixture("scheduler-ledger")

    // MARK: - Initializer
    // MARK: - Test
    @Test("The ledger records each slot's outcome")
    func ledgerRecordsSlotOutcomes() async throws {
        // Given
        let marker = try fixture.temporary.make("outcome").appendingPathComponent("m")
        let workflow = fixture.markerWorkflow(name: "wfo", marker: marker, tag: "S", sleep: 2.5)
        let wfDir = try fixture.temporary.make("outcome-wf")
        try fixture.write(workflow, to: wfDir)
        let workflowStore = fixture.catalog(directory: wfDir)
        let schedDir = try fixture.temporary.make("outcome-sched")
        try "id: ok\nworkflow: wfo\nevery: 1s\nconcurrency: skip\n"
        .write(to: schedDir.appendingPathComponent("ok.yaml"), atomically: true, encoding: .utf8)
        try "id: ghost\nworkflow: nope\nevery: 1s\n"
        .write(to: schedDir.appendingPathComponent("ghost.yaml"), atomically: true, encoding: .utf8)
        let ledger = FireLedger(path: try fixture.temporary.make("outcome-led").appendingPathComponent("l.json"))
        let scheduler = WorkflowScheduler(
            workflowStore: workflowStore,
            store: try fixture.scheduleStore(configDir: schedDir, runtimeDirectory: try fixture.temporary.make("sched-rt-a"), ids: ["ok": "wfo", "ghost": "nope"]),
            ledger: ledger, runner: fixture.runner(catalog: workflowStore), tickIntervalSeconds: 1)

        // When
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(1_200))
        await scheduler.tickOnce()
        var snapshot = await ledger.snapshot()

        // Then
        #expect(snapshot["ok"]?.state == .closed(.launched), "a slot enrolled in the run chain must close as launched")
        #expect(snapshot["ghost"]?.state == .closed(.denied(reason: "workflow_missing")), "a slot that fails resolution must close as denied(reason) — the reason is embedded in the outcome")
        try await Task.sleep(for: .milliseconds(1_200))
        await scheduler.tickOnce()
        snapshot = await ledger.snapshot()
        #expect(snapshot["ok"]?.state == .closed(.skipped), "a slot abandoned by policy must close as skipped")
        try await Task.sleep(for: .milliseconds(2_000))
    }

    @Test("Pruning survives a transient decode failure")
    func ledgerPruneSurvivesTransientDecodeFailure() async throws {
        // Given
        let wfDir = try fixture.temporary.make("live-wf")
        try fixture.write(fixture.markerWorkflow(
                name: "wfl", marker: fixture.temporary.make("live-m").appendingPathComponent("m"), tag: "S", sleep: 0),
            to: wfDir)
        let workflowStore = fixture.catalog(directory: wfDir)
        let configDir = try fixture.temporary.make("live-cfg")
        let schedFile = configDir.appendingPathComponent("keep.yaml")
        let body = "id: keep\nworkflow: wfl\nonce: \"2020-01-01 00:00:00\"\ntimezone: Asia/Seoul\n"
        try body.write(to: schedFile, atomically: true, encoding: .utf8)
        let ledger = FireLedger(path: try fixture.temporary.make("live-led").appendingPathComponent("l.json"))
        let scheduler = WorkflowScheduler(
            workflowStore: workflowStore,
            store: try fixture.scheduleStore(configDir: configDir, runtimeDirectory: try fixture.temporary.make("live-rt"), ids: ["keep": "wfl"]),
            ledger: ledger, runner: fixture.runner(catalog: workflowStore), tickIntervalSeconds: 1)

        // When
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(300))
        let fired = await ledger.snapshot()["keep"]

        // Then
        #expect(fired != nil, "the fire attempt must remain in the ledger")
        try "id: [broken".write(to: schedFile, atomically: true, encoding: .utf8)
        await scheduler.tickOnce()
        let duringBreak = await ledger.snapshot()["keep"]
        #expect(duringBreak != nil, "a decode failure is not declaration removal — wiping the fired ledger would re-fire the once on recovery")
        try body.write(to: schedFile, atomically: true, encoding: .utf8)
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(300))
        let restored = await ledger.snapshot()["keep"]
        #expect(restored?.attemptedSlot == fired?.attemptedSlot, "after recovery the same slot record persists — no re-fire (at-most-once)")
        try FileManager.default.removeItem(at: schedFile)
        await scheduler.tickOnce()
        let afterRemove = await ledger.snapshot()["keep"]
        #expect(afterRemove == nil, "when the declaration is removed, the ledger must be pruned (GC preserved)")
    }

    @Test("On load, pending is normalized to unknown")
    func loadNormalizesPendingToUnknown() async throws {
        // Given
        let directory = try fixture.temporary.make("pend-led")
        let path = directory.appendingPathComponent("fire-ledger.json")
        let object = ["x": ["attempted_at": ISO8601.string(Date()), "outcome": "pending"]]
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        let ledger = FireLedger(path: path)

        // When
        let record = await ledger.snapshot()["x"]

        // Then
        #expect(record?.state == .unknown, "pending on disk means the outcome is unknown — must normalize to unknown")
    }

    @Test("On persist failure it throws and leaves in-memory state clean")
    func recordThrowsOnPersistFailureAndKeepsInMemoryClean() async throws {
        // Given
        let ledger = FireLedger(path: try fixture.unwritableLedgerPath("rec"))
        do {

        // When
            try await ledger.recordAttempt(id: "x", slot: .fixture)

        // Then
            Issue.record("record must throw on persist failure")
        } catch {  }
        let fired = await ledger.lastAttempt(id: "x")
        #expect(fired == nil, "on disk persist failure, in-memory must not update either (blocks divergence)")
    }

    @Test("When persist fails, firing is deferred — at-most-once is upheld")
    func fireDeferredWhenPersistFails() async throws {
        // Given
        let marker = try fixture.temporary.make("persist-fail-m").appendingPathComponent("m")
        let workflow = fixture.markerWorkflow(name: "wfp", marker: marker, tag: "p", sleep: 0.1)
        let scheduler = try fixture.scheduler(
            workflows: [workflow],
            scheduleYAML: ["o": "id: o\nworkflow: wfp\nonce: \"2020-01-01 00:00:00\"\ntimezone: Asia/Seoul\n"],
            ledgerPath: try fixture.unwritableLedgerPath("fire"))

        // When
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(400))

        // Then
        #expect(fixture.read(marker) == "", "must not fire without a durable anchor (the buggy version yields 'p')")
    }

    @Test("No double fire across restart after persist recovers")
    func noDoubleFireAcrossRestartAfterPersistRecovers() async throws {
        // Given
        let base = try fixture.temporary.make("restart")
        let blocker = base.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let ledgerPath = blocker.appendingPathComponent("sub").appendingPathComponent("l.json")
        let marker = try fixture.temporary.make("restart-m").appendingPathComponent("m")
        let workflow = fixture.markerWorkflow(name: "wfr", marker: marker, tag: "o", sleep: 0.1)
        let onceYAML = "id: o\nworkflow: wfr\nonce: \"2020-01-01 00:00:00\"\ntimezone: Asia/Seoul\n"
        let schedA = try fixture.scheduler(
            workflows: [workflow], scheduleYAML: ["o": onceYAML], ledgerPath: ledgerPath)

        // When
        await schedA.tickOnce()
        try await Task.sleep(for: .milliseconds(400))

        // Then
        #expect(fixture.read(marker) == "", "tickA (ledger broken): must not fire")
        try FileManager.default.removeItem(at: blocker)
        let schedB = try fixture.scheduler(
            workflows: [workflow], scheduleYAML: ["o": onceYAML], ledgerPath: ledgerPath)
        await schedB.tickOnce()
        try await Task.sleep(for: .milliseconds(400))
        #expect(fixture.read(marker) == "o", "restart after recovery: must fire exactly once (the buggy version yields 'oo')")
    }

    @Test("clear and prune also throw on persist failure and protect memory")
    func clearAndPruneThrowOnPersistFailureKeepingInMemory() async throws {
        // Given
        let directory = try fixture.temporary.make("cp-led")
        let path = directory.appendingPathComponent("l.json")
        let ledger = FireLedger(path: path)

        // When
        try await ledger.recordAttempt(id: "k", slot: .fixture)
        let seeded = await ledger.lastAttempt(id: "k")

        // Then
        #expect(seeded != nil)
        try FileManager.default.removeItem(at: path)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        do {
            try await ledger.clear(id: "k")
            Issue.record("clear must throw on persist failure")
        } catch {  }
        let afterClear = await ledger.lastAttempt(id: "k")
        #expect(afterClear != nil, "on clear persist failure the in-memory entry is kept (the safe direction)")
        do {
            try await ledger.prune(liveIDs: [])
            Issue.record("prune must throw on persist failure")
        } catch {  }
        let afterPrune = await ledger.lastAttempt(id: "k")
        #expect(afterPrune != nil, "on prune persist failure the in-memory entry is kept")
    }

    @Test("A corrupt ledger is surfaced, not silently skipped")
    func loadCorruptLedgerSurfacesNotSilent() async throws {
        // Given
        let directory = try fixture.temporary.make("corrupt-led")
        let path = directory.appendingPathComponent("fire-ledger.json")
        try "[1,2,3]".write(to: path, atomically: true, encoding: .utf8)
        var ledger: FireLedger?

        // When
        let error = try await StandardErrorCapture.capture { ledger = FireLedger(path: path) }
        let snapshot = await ledger!.snapshot()

        // Then
        #expect(snapshot.isEmpty, "an unparsable ledger degrades to empty")
        #expect(error.contains("fire-ledger") && error.contains("re-fire"), "a ledger that exists but cannot be read must surface (the buggy version is silent)")
    }

    @Test("A fast-forwarded anchor survives restart")
    func fastForwardAnchorIsDurable() async throws {
        // Given
        let marker = try fixture.temporary.make("ff").appendingPathComponent("m")
        let workflow = fixture.markerWorkflow(name: "wfff", marker: marker, tag: "x", sleep: 0)
        let ledgerPath = try fixture.temporary.make("ff-ledger").appendingPathComponent("fire-ledger.json")
        let now = Date()
        try JSONSerialization
        .data(withJSONObject: ["ff": ISO8601.string(now.addingTimeInterval(-5))], options: [])
        .write(to: ledgerPath)
        let scheduler = try fixture.scheduler(
            workflows: [workflow],
            scheduleYAML: ["ff": "id: ff\nworkflow: wfff\nevery: 1s\n"],
            ledgerPath: ledgerPath)

        // When
        await scheduler.tickOnce()
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: ledgerPath)) as! [String: [String: String]]

        // Then
        let attemptedAt = try #require(raw["ff"]?["attempted_at"])
        let anchor = try #require(ISO8601.parse(attemptedAt))
        #expect(anchor > now.addingTimeInterval(-1.5), "fast-forward anchor not durable — ledger kept a stale slot; a restart would re-fire skipped slots")
    }

    // MARK: - Private
}
