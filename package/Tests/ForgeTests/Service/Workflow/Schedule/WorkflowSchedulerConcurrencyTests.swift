//
//  WorkflowSchedulerConcurrencyTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

/// How overlapping fires are handled — skip/queue/replace policies and non-blocking firing.
@Suite("WorkflowSchedulerConcurrency Tests")
struct WorkflowSchedulerConcurrencyTests {
    // MARK: - Property
    private let fixture = SchedulerFixture("scheduler-concurrency")

    // MARK: - Initializer
    // MARK: - Test
    @Test("Fires do not block each other and schedules run concurrently")
    func fireIsNonBlockingAndRunsSchedulesConcurrently() async throws {
        // Given
        let marker = try fixture.temporary.make("nb").appendingPathComponent("m")
        let wfA = fixture.markerWorkflow(name: "wfa", marker: marker, tag: "A", sleep: 0.5)
        let wfB = fixture.markerWorkflow(name: "wfb", marker: marker, tag: "B", sleep: 0.5)
        let scheduler = try fixture.scheduler(
            workflows: [wfA, wfB],
            scheduleYAML: [
                "a": "id: a\nworkflow: wfa\nevery: 1s\n",
                "b": "id: b\nworkflow: wfb\nevery: 1s\n",
        ])
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(1_100))
        let start = ContinuousClock.now
        await scheduler.tickOnce()
        let elapsedMs = (ContinuousClock.now - start).milliseconds

        // Then
        #expect(elapsedMs < 300, "fire must be non-blocking — the tick must not wait for workflow (0.5s) completion (actual: \(elapsedMs)ms)")
        try await Task.sleep(for: .milliseconds(900))
        let output = fixture.read(marker)
        #expect(output.contains("A"), "wfa should have run (marker: '\(output)')")
        #expect(output.contains("B"), "wfb should have run (marker: '\(output)')")
    }

    @Test("The skip policy drops an overlapping fire")
    func skipPolicyDropsOverlappingFire() async throws {
        // Given
        let marker = try fixture.temporary.make("skip").appendingPathComponent("m")
        let workflow = fixture.markerWorkflow(name: "wfslow", marker: marker, tag: "x", sleep: 2.0)
        let scheduler = try fixture.scheduler(
            workflows: [workflow],
            scheduleYAML: ["s": "id: s\nworkflow: wfslow\nevery: 1s\nconcurrency: skip\n"])

        // When
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(1_200))
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(1_200))
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(1_400))

        // Then
        #expect(fixture.read(marker) == "x", "the second fire must be skipped, leaving exactly one run")
    }

    @Test("The queue policy lines fires up instead of dropping them")
    func queuePolicySerializesOverlappingFire() async throws {
        // Given
        let marker = try fixture.temporary.make("queue").appendingPathComponent("m")
        let workflow = fixture.markerWorkflow(name: "wfq", marker: marker, tag: "S", sleep: 1.5, endTag: "E")
        let scheduler = try fixture.scheduler(
            workflows: [workflow],
            scheduleYAML: ["q": "id: q\nworkflow: wfq\nevery: 1s\n"])
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(1_200))
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(1_200))
        let start = ContinuousClock.now
        await scheduler.tickOnce()
        let elapsedMs = (ContinuousClock.now - start).milliseconds

        // Then
        #expect(elapsedMs < 300, "a queued fire must also be non-blocking — waiting for the prior run belongs inside the task (actual: \(elapsedMs)ms)")
        try await Task.sleep(for: .milliseconds(3_500))
        #expect(fixture.read(marker) == "SESE", "queue must run serially without overlap (SSEE=overlap, SE=drop)")
    }

    @Test("The replace policy cancels the previous run and starts fresh")
    func replacePolicyCancelsPreviousRun() async throws {
        // Given
        let marker = try fixture.temporary.make("replace").appendingPathComponent("m")
        let workflow = fixture.markerWorkflow(name: "wfr", marker: marker, tag: "S", sleep: 2.0, endTag: "E")
        let scheduler = try fixture.scheduler(
            workflows: [workflow],
            scheduleYAML: ["r": "id: r\nworkflow: wfr\nevery: 1s\nconcurrency: replace\n"])

        // When
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(1_200))
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(1_200))
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(3_000))

        // Then
        #expect(fixture.read(marker) == "SSE", "replace must cancel run1 before its E and run run2 to completion (SESE=cancel failed, SE=drop)")
    }

    @Test("When the new run fails resolution, the prior run is kept alive")
    func replaceResolveFailureKeepsPriorRunAlive() async throws {
        // Given
        let marker = try fixture.temporary.make("den-rep").appendingPathComponent("m")
        let workflow = fixture.markerWorkflow(name: "wfr", marker: marker, tag: "S", sleep: 1.5, endTag: "E")
        let wfDir = try fixture.temporary.make("den-rep-wf")
        try fixture.write(workflow, to: wfDir)
        let workflowStore = fixture.catalog(directory: wfDir)
        let schedDir = try fixture.temporary.make("den-rep-sched")
        try "id: r\nworkflow: wfr\nevery: 1s\nconcurrency: replace\n"
        .write(to: schedDir.appendingPathComponent("r.yaml"), atomically: true, encoding: .utf8)
        let scheduler = WorkflowScheduler(
            workflowStore: workflowStore,
            store: try fixture.scheduleStore(configDir: schedDir, runtimeDirectory: try fixture.temporary.make("sched-rt-b"), ids: ["r": "wfr"]),
            ledger: FireLedger(path: try fixture.temporary.make("den-rep-led").appendingPathComponent("l.json")),
            runner: fixture.runner(catalog: workflowStore),
            tickIntervalSeconds: 1
        )

        // When
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(1_200))
        await scheduler.tickOnce()
        try FileManager.default.removeItem(at: wfDir.appendingPathComponent("wfr.yaml"))
        try await Task.sleep(for: .milliseconds(1_200))
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(1_500))

        // Then
        #expect(fixture.read(marker) == "SE", "a replace fire that fails resolution must not cancel the prior run (S=cancelled, SSE-like=re-fired)")
    }

    @Test("After a stall, missed slots are not fired in a burst")
    func everyDoesNotBurstAfterStall() async throws {
        // Given
        let marker = try fixture.temporary.make("burst").appendingPathComponent("m")
        let workflow = fixture.markerWorkflow(name: "wfb", marker: marker, tag: "x", sleep: 0.1)
        let scheduler = try fixture.scheduler(
            workflows: [workflow],
            scheduleYAML: ["e": "id: e\nworkflow: wfb\nevery: 1s\n"])

        // When
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(3_500))
        await scheduler.tickOnce()
        await scheduler.tickOnce()
        try await Task.sleep(for: .milliseconds(500))

        // Then
        #expect(fixture.read(marker) == "x", "after a stall it must catch up exactly once (a burst yields 'xx' or more)")
    }

    // MARK: - Private
}
