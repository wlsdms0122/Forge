//
//  WorkflowPoolShutdownTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import Forge

@Suite("WorkflowPoolShutdown Tests")
struct WorkflowPoolShutdownTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("No new registrations are accepted while shutting down")
    func shutdownRefusesNewRegistrations() async throws {
        // Given
        let pool = WorkflowPool(maximumConcurrentSteps: 2, maximumActiveRuns: 8)
        try await pool.register(workflowID: "r1", workflowName: "a", rootID: "r1",
            origin: .rpc, principal: "cli:t")
        await pool.beginShutdown()
        do {
            try await pool.register(workflowID: "r2", workflowName: "b", rootID: "r2",
                origin: .rpc, principal: "cli:t")

        // Then
            Issue.record("New runs should be rejected while draining")
        } catch let error as PoolShuttingDown {
            #expect(error.message.contains("draining"), Comment(rawValue: error.message))
            #expect(!(error is any WorkFailure), "A shutdown rejection must carry no stamp — a fallback must not fake success on a dying daemon")
        }
        
        let hadRun = await pool.cancel(workflowID: "r1")
        #expect(hadRun)
    }
    
    @Test("Drain cancels what remains and reports what was left over")
    func drainCancelsAndReportsLeftover() async throws {
        // Given
        let pool = WorkflowPool(maximumConcurrentSteps: 2, maximumActiveRuns: 8)
        try await pool.register(workflowID: "stuck", workflowName: "w", rootID: "stuck",
            origin: .rpc, principal: "cli:t")

        // When
        await pool.beginShutdown()
        let leftover = await pool.drain(graceSeconds: 0.3)

        // Then
        #expect(leftover.map(\.workflowID) == ["stuck"], "Unfinished runs are reported as leftover")
        #expect(leftover.first?.state == .cancelling, "Cancellation should be in progress")
        await pool.unregister(workflowID: "stuck")
        let empty = await pool.drain(graceSeconds: 0.3)
        #expect(empty.isEmpty)
    }
    
    // MARK: - Private
}
