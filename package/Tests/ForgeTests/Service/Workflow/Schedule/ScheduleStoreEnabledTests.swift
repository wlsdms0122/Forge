//
//  ScheduleStoreEnabledTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

/// On/off lives in the ledger, not the definition file — the machine never rewrites human-authored YAML.
@Suite("ScheduleStoreEnabled Tests")
struct ScheduleStoreEnabledTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("schedule-enabled")

    // MARK: - Initializer
    // MARK: - Test
    // MARK: - setEnabled — enabled ledger (definition file immutable)
    @Test("On/off does not touch the other fields")
    func setEnabledPreservesAllOtherFields() async throws {
        // Given
        let directory = try temporary.make("toggle-cfg"); defer { try? FileManager.default.removeItem(at: directory) }
        let runtimeDirectoryectory = try temporary.make("toggle-rt"); defer { try? FileManager.default.removeItem(at: runtimeDirectoryectory) }
        let stateFile = runtimeDirectoryectory.appendingPathComponent("enabled-overrides.json")
        let store = ScheduleStore(configDir: directory, runtimeDirectory: runtimeDirectoryectory, stateFile: stateFile)
        let created = try await store.create(Schedule(
                id: "tog", workflow: "wf-x",
                trigger: .every(Interval(seconds: 90)),
                concurrency: .skip,
                enabled: true,
                inputs: ["scope": .string("quick"), "limit": .int(5)],
                spec: .object(["steps": .array([])])))

        // When
        try await store.setEnabled(id: created.id, enabled: false, authorizedWorkflow: "wf-x")
        let fetched = await store.lookup(created.id)

        // Then
        let after = try #require(fetched)
        #expect(after.enabled == false, "enabled must be toggled via the ledger stamp")
        #expect(after.workflow == "wf-x")
        #expect(after.trigger == .every(Interval(seconds: 90)))
        #expect(after.concurrency == .skip, "concurrency preserved (a field that would be lost under re-serialization drift)")
        #expect(after.inputs?["scope"] == .string("quick"))
        #expect(after.inputs?["limit"] == .int(5))
        #expect(after.spec == .object(["steps": .array([]), "name": .string("<inline>")]), "spec preserved + anonymous sigil")
    }

    @Test("The definition file is never rewritten — even human-written comments stay intact")
    func setEnabledDoesNotRewriteDefinitionFile() async throws {
        // Given
        let directory = try temporary.make("norewrite"); defer { try? FileManager.default.removeItem(at: directory) }
        let state = try temporary.file("schedule-enabled.json")
        let defURL = directory.appendingPathComponent("nr.yaml")
        let body = #"""
        id: nr
        workflow: wf
        every: 1h
        # human-written comment — the machine must not squash it
        """#
        try body.write(to: defURL, atomically: true, encoding: .utf8)
        let store = ScheduleStore(configDir: directory, stateFile: state)

        // When
        let initial = await store.lookup("nr")?.enabled

        // Then
        #expect(initial == false, "a schedule absent from the ledger starts disabled")
        let mtimeBefore = try FileManager.default.attributesOfItem(atPath: defURL.path)[.modificationDate] as? Date
        try await store.setEnabled(id: "nr", enabled: true, authorizedWorkflow: "wf")
        let contentAfter = try String(contentsOf: defURL, encoding: .utf8)
        let mtimeAfter = try FileManager.default.attributesOfItem(atPath: defURL.path)[.modificationDate] as? Date
        #expect(contentAfter == body, "definition file content must be untouched (comments included)")
        #expect(mtimeAfter == mtimeBefore, "definition file mtime must not change either")
        let afterToggle = await store.lookup("nr")?.enabled
        #expect(afterToggle == true, "the effect reaches lookup via the ledger stamp")
        #expect(readEnabled(state)["nr"] == "wf", "must be recorded in the enabled ledger as (id, workflow)")
    }

    @Test("The effect is recorded as ledger membership")
    func setEnabledUpdatesLedgerMembership() async throws {
        // Given
        let directory = try temporary.make("member"); defer { try? FileManager.default.removeItem(at: directory) }
        let state = try temporary.file("schedule-enabled.json")
        try #"""
        id: cv
        workflow: wf
        every: 1h
        """#.write(to: directory.appendingPathComponent("cv.yaml"), atomically: true, encoding: .utf8)
        let store = ScheduleStore(configDir: directory, stateFile: state)

        // When
        try await store.setEnabled(id: "cv", enabled: true, authorizedWorkflow: "wf")

        // Then
        #expect(readEnabled(state)["cv"] == "wf", "enabling must add it to the ledger")
        let enabled = await store.lookup("cv")?.enabled
        #expect(enabled == true)
        try await store.setEnabled(id: "cv", enabled: false, authorizedWorkflow: "wf")
        #expect(readEnabled(state)["cv"] == nil, "disabling must remove it from the ledger")
        let off = await store.lookup("cv")?.enabled
        #expect(off == false)
    }

    @Test("Writing an enabled key in the definition file is rejected")
    func declarationEnabledKeyRejected() async throws {
        // Given
        let directory = try temporary.make("declkey"); defer { try? FileManager.default.removeItem(at: directory) }
        try #"""
        id: gh
        workflow: wf
        every: 1h
        enabled: true
        """#.write(to: directory.appendingPathComponent("gh.yaml"), atomically: true, encoding: .utf8)
        let store = ScheduleStore(configDir: directory, stateFile: try temporary.file("schedule-enabled.json"))

        // When
        let loaded = await store.lookup("gh")

        // Then
        #expect(loaded == nil, "a file declaring enabled must be refused at load")
        let failures = await store.catalog().failures
        #expect(failures.contains { failure in failure.reason.contains("enabled") }, "the refusal reason must surface via failures — got: \(failures.map(\.reason))")
    }

    @Test("State survives restart, and losing the ledger fails safe toward disabled")
    func enabledStateSurvivesRestartAndLedgerLossFailsSafe() async throws {
        // Given
        let directory = try temporary.make("restart"); defer { try? FileManager.default.removeItem(at: directory) }
        let state = try temporary.file("schedule-enabled.json")
        for id in ["on1", "off1"] {
            try """
            workflow: wf
            every: 1h
            """.write(to: directory.appendingPathComponent("\(id).yaml"), atomically: true, encoding: .utf8)
        }
        
        let store = ScheduleStore(configDir: directory, stateFile: state)
        try await store.setEnabled(id: "on1", enabled: true, authorizedWorkflow: "wf")
        let reborn = ScheduleStore(configDir: directory, stateFile: state)

        // When
        let enabled = await reborn.lookup("on1")?.enabled
        let off = await reborn.lookup("off1")?.enabled

        // Then
        #expect(enabled == true, "the enabled state must survive a restart")
        #expect(off == false, "what was never enabled must stay disabled")
        try FileManager.default.removeItem(at: state)
        let amnesiac = ScheduleStore(configDir: directory, stateFile: state)
        let lost = await amnesiac.lookup("on1")?.enabled
        #expect(lost == false, "with no ledger, treat as not enabled (the safe direction)")
    }

    @Test("Reusing an id under a different workflow does not inherit the enabled state")
    func enabledDoesNotSurviveIdReuseWithDifferentWorkflow() async throws {
        // Given
        let directory = try temporary.make("reuse"); defer { try? FileManager.default.removeItem(at: directory) }
        let state = try temporary.file("schedule-enabled.json")
        let defURL = directory.appendingPathComponent("ru.yaml")
        try "workflow: original\nevery: 1h\n".write(to: defURL, atomically: true, encoding: .utf8)
        let store = ScheduleStore(configDir: directory, stateFile: state)

        // When
        try await store.setEnabled(id: "ru", enabled: true, authorizedWorkflow: "original")
        let enabled = await store.lookup("ru")?.enabled

        // Then
        #expect(enabled == true)
        try await Task.sleep(for: .seconds(1))
        try "workflow: hijacker\nevery: 1h\n".write(to: defURL, atomically: true, encoding: .utf8)
        let reused = await store.lookup("ru")?.enabled
        #expect(reused == false, "when a different definition reuses the id, the old enablement intent must not resurrect")
    }

    @Test("A corrupt ledger fails safe, surfaces the fact, then recovers")
    func corruptLedgerFailsSafeAndSurfacesThenRecovers() async throws {
        // Given
        let directory = try temporary.make("corrupt"); defer { try? FileManager.default.removeItem(at: directory) }
        let state = try temporary.file("schedule-enabled.json")
        try #"""
        id: cs
        workflow: wf
        every: 1h
        """#.write(to: directory.appendingPathComponent("cs.yaml"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: state.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try "{not json[".write(to: state, atomically: true, encoding: .utf8)
        let store = ScheduleStore(configDir: directory, stateFile: state)

        // When
        let effective = await store.lookup("cs")?.enabled

        // Then
        #expect(effective == false, "a corrupt ledger must behave as all-disabled (never toward re-firing)")
        let failures = await store.catalog().failures
        #expect(failures.contains { failure in failure.reason.contains("enabled-ledger") }, "ledger corruption must surface via failures — got: \(failures.map(\.reason))")
        #expect(!FileManager.default.fileExists(atPath: state.path), "the corrupt ledger must be quarantined away from its original location")
        let quarantined = try FileManager.default.contentsOfDirectory(
            at: state.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        .filter { url in url.lastPathComponent.contains(".corrupt-") }
        #expect(quarantined.count == 1, "the quarantined copy must be preserved")
        try await store.setEnabled(id: "cs", enabled: true, authorizedWorkflow: "wf")
        let recovered = await store.lookup("cs")?.enabled
        #expect(recovered == true)
        #expect(readEnabled(state) == ["cs": "wf"], "the rewritten ledger must be a valid {id: workflow} map")
        let cleared = await store.catalog().failures
        #expect(!cleared.contains { failure in failure.reason.contains("enabled-ledger") }, "after a valid rewrite, the corruption marker must be cleared")
    }

    @Test("Strings that look sexagesimal round-trip verbatim")
    func createRoundTripsSexagesimalString() async throws {
        let runtimeDirectoryectory = try temporary.make("sexagesimal"); defer { try? FileManager.default.removeItem(at: runtimeDirectoryectory) }
        let state = try temporary.file("schedule-enabled.json")
        let store = ScheduleStore(configDir: nil, runtimeDirectory: runtimeDirectoryectory, stateFile: state)
        let created = try await store.create(Schedule(
                id: "sg", workflow: "wf",
                trigger: .every(Interval(seconds: 3600)),
                inputs: ["at_time": .string("09:20"), "window": .string("09:20:00"), "n": .int(5)]))
        let fresh = ScheduleStore(configDir: nil, runtimeDirectory: runtimeDirectoryectory, stateFile: state)
        let decoded = await fresh.lookup(created.id)
        #expect(decoded?.inputs?["at_time"] == .string("09:20"), "a time-of-day-looking string must not degrade into a sexagesimal number")
        #expect(decoded?.inputs?["window"] == .string("09:20:00"))
        #expect(decoded?.inputs?["n"] == .int(5))
    }

    @Test("Mutation is rejected when identity changed after authorization")
    func mutationRejectsWhenScheduleIdentityChangedAfterAuthorization() async throws {
        let directory = try temporary.make("toctou"); defer { try? FileManager.default.removeItem(at: directory) }
        let stateDir = try temporary.make("toctou-state"); defer { try? FileManager.default.removeItem(at: stateDir) }
        let stateFile = stateDir.appendingPathComponent("overrides.json")
        let defURL = directory.appendingPathComponent("tc.yaml")
        try #"""
        id: tc
        workflow: victim
        every: 1h
        """#.write(to: defURL, atomically: true, encoding: .utf8)
        let store = ScheduleStore(configDir: directory, stateFile: stateFile)
        do {
            try await store.setEnabled(id: "tc", enabled: true, authorizedWorkflow: "attacker-owned")
            Issue.record("setEnabled must refuse when identity mismatches")
        } catch { #expect("\(error)".contains("changed underneath")) }
        do {
            try await store.delete(id: "tc", authorizedWorkflow: "attacker-owned")
            Issue.record("delete must refuse when identity mismatches")
        } catch { #expect("\(error)".contains("changed underneath")) }
        let untouched = await store.lookup("tc")
        #expect(untouched?.enabled == false)
        try await store.setEnabled(id: "tc", enabled: true, authorizedWorkflow: "victim")
        let toggled = await store.lookup("tc")?.enabled
        #expect(toggled == true)
        try await store.delete(id: "tc", authorizedWorkflow: "victim")
        let gone = await store.lookup("tc")
        #expect(gone == nil)
    }

    @Test("withEnabled is a copy that preserves the other fields")
    func withEnabledIsFieldPreservingCopy() {
        let schedule = Schedule(id: "a", workflow: "w", trigger: .every(Interval(seconds: 30)),
            concurrency: .replace, enabled: true,
            inputs: ["x": .int(1)], spec: .string("s"))
        let disabled = schedule.withEnabled(false)
        #expect(disabled.enabled == false)
        #expect(disabled.id == "a")
        #expect(disabled.workflow == "w")
        #expect(disabled.trigger == .every(Interval(seconds: 30)))
        #expect(disabled.concurrency == .replace)
        #expect(disabled.inputs?["x"] == .int(1))
        #expect(disabled.spec == .string("s"))
        #expect(schedule.enabled == true, "original unchanged (value semantics)")
    }
    // MARK: - Private
    private func readEnabled(_ url: URL) -> [String: String] {
        guard
            let data = try? Data(contentsOf: url),
            let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
        else {
            return [:]
        }

        return raw
    }
}
