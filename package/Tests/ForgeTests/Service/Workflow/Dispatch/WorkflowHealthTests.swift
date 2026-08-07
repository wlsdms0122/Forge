//
//  WorkflowHealthTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("WorkflowHealth Tests")
struct WorkflowHealthTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    // MARK: (1) run cap
    @Test("Refuses at the cap and reports which tree is full")
    func registerRefusesAtCapWithTreeDiagnostics() async throws {
        // Given
        let pool = WorkflowPool(maximumConcurrentSteps: 1, maximumActiveRuns: 2)
        try await pool.register(workflowID: "r1", workflowName: "loop", rootID: "root-A",
            origin: .manual, principal: "t")
        try await pool.register(workflowID: "r2", workflowName: "loop", rootID: "root-A",
            origin: .manual, principal: "t")
        do {
            try await pool.register(workflowID: "r3", workflowName: "loop", rootID: "root-A",
                origin: .manual, principal: "t")

        // Then
            Issue.record("Should be refused when the cap is reached")
        } catch {
            let message = "\(error)"
            #expect(message.contains("active run cap (2)"), Comment(rawValue: message))
            #expect(message.contains("root-A=2"), Comment(rawValue: message))
        }
        
        let health = await pool.health()
        #expect(health.refusedRuns == 1)
        #expect(health.activeRuns == 2)
    }
    
    @Test("The same registration is not double-counted even at the cap")
    func registerIdempotentAtCap() async throws {
        // Given
        let pool = WorkflowPool(maximumConcurrentSteps: 1, maximumActiveRuns: 1)
        try await pool.register(workflowID: "r1", workflowName: "wf", rootID: "r1",
            origin: .manual, principal: "t")
        try await pool.register(workflowID: "r1", workflowName: "wf", rootID: "r1",
            origin: .manual, principal: "t")

        // When
        let health = await pool.health()

        // Then
        #expect(health.activeRuns == 1)
        #expect(health.refusedRuns == 0)
    }
    
    @Test("Unregistering frees a cap slot")
    func capFreesOnUnregister() async throws {
        // Given
        let pool = WorkflowPool(maximumConcurrentSteps: 1, maximumActiveRuns: 1)
        try await pool.register(workflowID: "r1", workflowName: "wf", rootID: "r1",
            origin: .manual, principal: "t")
        await pool.unregister(workflowID: "r1")
        try await pool.register(workflowID: "r2", workflowName: "wf", rootID: "r2",
            origin: .manual, principal: "t")

        // When
        let health = await pool.health()

        // Then
        #expect(health.activeRuns == 1)
    }
    
    @Test("Fails loudly at the run cap instead of passing silently")
    func dispatcherFailsLoudAtRunCap() async throws {
        // Given
        let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("forge-health-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try #"""
        steps:
          - id: x
            shell:
              command: ["/bin/echo", "ok"]
        """#.write(
            to: directory.appendingPathComponent("echo3.yaml"), atomically: true, encoding: .utf8)
        let pool = WorkflowPool(maximumConcurrentSteps: 1, maximumActiveRuns: 1)

        let store = SpecCatalog(directory: directory, loader: ForgeSpec.loader())
        let runner = SpecWorkflowRunner(
            catalog: store,
            eventBus: WorkflowEventBus(),
            policyStore: PolicyStore(seed: ["*": ["*"]]),
            pool: pool,
            workRegistry: WorkRegistry(),
            tokenAuthority: TokenAuthority(),
            shell: LiveShell(),
            agent: LiveAgent(executor: Executor(backend: StubBackend("noop"))),
            resources: LiveResources(store: ResourceStore(directory: nil)))
        try await pool.register(workflowID: "occupier", workflowName: "other", rootID: "occupier",
            origin: .manual, principal: "t")
        let program = try await store.spec(named: "echo3")
        do {
            _ = try await runner.dispatch(
                program: program, name: "echo3", inputs: [:], principal: "cli:t",
                origin: .rpc, mode: .awaited)

        // Then
            Issue.record("Dispatch beyond the run cap should be refused")
        } catch {
            #expect("\(error)".contains("active run cap"), "\(error)")
        }
    }
    
    // MARK: (2) health surface
    @Test("The health snapshot aggregates trees and rate together")
    func healthSnapshotAggregatesTreesAndRate() async throws {
        // Given
        let pool = WorkflowPool(maximumConcurrentSteps: 2, maximumActiveRuns: 10)
        try await pool.register(workflowID: "a1", workflowName: "turn", rootID: "root-A",
            origin: .manual, principal: "t")
        try await pool.register(workflowID: "a2", workflowName: "bot-invoke", rootID: "root-A",
            origin: .manual, principal: "t")
        try await pool.register(workflowID: "b1", workflowName: "worker", rootID: "root-B",
            origin: .manual, principal: "t")

        // When
        let health = await pool.health()

        // Then
        #expect(health.activeRuns == 3)
        #expect(health.dispatchesLast60s == 3)
        #expect(health.trees.first?.rootID == "root-A")
        #expect(health.trees.first?.count == 2)
        #expect(health.trees.first?.names["bot-invoke"] == 1)
        #expect(health.oldestRuns.count == 3)
        #expect(health.slotsMax == 2)
        #expect(health.slotsFree == 2)
        #expect(health.waiters.isEmpty)
    }
    
    @Test("Advisory flags are derived from state")
    func advisoryFlags() {
        // Given
        typealias H = WorkflowPool.HealthSnapshot
        let quiet = H(slotsMax: 5, slotsFree: 5, waiters: [], activeRuns: 1, runCap: 256,
            refusedRuns: 0,
            oldestRuns: [.init(workflowID: "w", workflowName: "n", state: "running", ageMs: 1000)],
            trees: [.init(rootID: "r", count: 1, names: ["n": 1])],
            dispatchesLast60s: 2, refusedLast60s: 0)

        // Then
        #expect(WorkflowHealthMethod.computeFlags(quiet).isEmpty)
        let pastRefusalsOnly = H(slotsMax: 5, slotsFree: 5, waiters: [], activeRuns: 1, runCap: 256,
            refusedRuns: 5,
            oldestRuns: [], trees: [],
            dispatchesLast60s: 2, refusedLast60s: 0)
        #expect(WorkflowHealthMethod.computeFlags(pastRefusalsOnly).isEmpty, "Accumulated refusals outside the window alone do not turn on the runs_refused flag")
        let noisy = H(slotsMax: 5, slotsFree: 0,
            waiters: [.init(workflowID: "w1", waitedMs: 61_000)],
            activeRuns: 20, runCap: 256, refusedRuns: 3,
            oldestRuns: [.init(workflowID: "w2", workflowName: "n", state: "running", ageMs: 1_900_000)],
            trees: [.init(rootID: "r", count: 17, names: ["loop": 17])],
            dispatchesLast60s: 31, refusedLast60s: 3)
        let flags = WorkflowHealthMethod.computeFlags(noisy)
        let kinds = Set(flags.compactMap { flag in flag["kind"] as? String })
        #expect(kinds == ["long_wait", "long_run", "big_tree", "high_rate", "runs_refused"])
        let byClass = Dictionary(grouping: flags, by: { flag in flag["class"] as? String ?? "?" })
        .mapValues { group in Set(group.compactMap { flag in flag["kind"] as? String }) }
        #expect(byClass["saturation"] == ["long_wait", "runs_refused"])
        #expect(byClass["anomaly"] == ["long_run", "big_tree", "high_rate"])
    }
    
    @Test("The refusal window clears itself without a restart — the cumulative stat remains")
    func runsRefusedWindowSelfClears() async throws {
        // Given
        let pool = WorkflowPool(maximumConcurrentSteps: 1, maximumActiveRuns: 1)
        try await pool.register(workflowID: "r1", workflowName: "wf", rootID: "r1",
            origin: .manual, principal: "t")
        do {
            try await pool.register(workflowID: "r2", workflowName: "wf", rootID: "r2",
                origin: .manual, principal: "t")

        // Then
            Issue.record("Should be refused when the cap is reached")
        } catch {
            #expect(error is RunCapExceeded, "\(error)")
        }
        
        let healthNow = await pool.health()
        #expect(healthNow.refusedLast60s == 1, "Right after the refusal — inside the window, so the flag's basis is live")
        #expect(healthNow.refusedRuns == 1)
        let healthAfterMinute = await pool.health(now: ContinuousClock.now.advanced(by: .seconds(61)))
        #expect(healthAfterMinute.refusedLast60s == 0, "Outside the window — clears itself without a restart (no latching)")
        #expect(healthAfterMinute.refusedRuns == 1, "The cumulative stat persists")
    }
    
    // MARK: - Private
}
