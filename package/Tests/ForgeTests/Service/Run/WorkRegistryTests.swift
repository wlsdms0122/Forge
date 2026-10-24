//
//  WorkRegistryTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("WorkRegistry Tests")
struct WorkRegistryTests {
    private final class ClosedFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func mark() { lock.lock(); value = true; lock.unlock() }
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("Updating the span changes only the span")
    func updateSpanChangesOnlySpan() async {
        // Given
        let registry = WorkRegistry()

        // When
        await registerOne(registry, span: "s-root")
        let before = await registry.lookup(workflowID: "r-test")

        // Then
        #expect(before?.nodeID == "s-root")
        await registry.updateSpan(workflowID: "r-test", nodeID: "s-invoke")
        let record = await registry.lookup(workflowID: "r-test")
        #expect(record?.nodeID == "s-invoke", "The span should be updated")
        #expect(record?.workflowID == "r-test")
        #expect(record?.workflowName == "response")
        #expect(record?.principal == "cli:response")
        #expect(record?.rootID == "t-abc")
    }
    
    @Test("Preserves all other fields, including optionals")
    func updateSpanPreservesAllFieldsIncludingOptionals() async {
        // Given
        let registry = WorkRegistry()
        await registry.register(WorkRecord(
                workflowID: "r-full", workflowName: "wf",
                principal: "cli:wf", origin: .schedule("sched-1"),
                rootID: "root-1", nodeID: "n0",
                correlator: "corr-9", parameters: ["session": .string("s1")]))

        // When
        await registry.updateSpan(workflowID: "r-full", nodeID: "n1")
        let record = await registry.lookup(workflowID: "r-full")

        // Then
        #expect(record?.nodeID == "n1", "Span updated")
        #expect(record?.origin.kind == "schedule", "Origin preserved")
        #expect(record?.origin.id == "sched-1")
        #expect(record?.correlator == "corr-9", "Correlator preserved")
        #expect(record?.parameters?["session"] == .string("s1"), "Parameters preserved")
    }
    
    @Test("Updating the span of an unknown workflow is a no-op")
    func updateSpanUnknownWorkflowIsNoop() async {
        let registry = WorkRegistry()
        await registry.updateSpan(workflowID: "r-missing", nodeID: "s-x")
    }
    
    @Test("Release removes the record")
    func releaseRemovesRecord() async {
        // Given
        let registry = WorkRegistry()

        // When
        await registerOne(registry, span: "s-root")
        await registry.release(workflowID: "r-test")
        let after = await registry.lookup(workflowID: "r-test")

        // Then
        #expect(after == nil)
    }
    
    // MARK: - touch lifetime gate (regression guard for the finding confirmed in the 08-03 audit)
    @Test("Beginning close drains in-flight touches and blocks new ones")
    func beginCloseDrainsInflightTouchesAndRejectsNewOnes() async {
        // Given
        let registry = WorkRegistry()

        // When
        await registerOne(registry, span: nil)
        let approved = await registry.beginTouch(workflowID: "r-test")

        // Then
        #expect(approved, "A touch on a live run should be approved")
        let closeDone = ClosedFlag()
        let closeTask = Task {
            await registry.beginClose(workflowID: "r-test")
            closeDone.mark()
        }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!closeDone.isSet, "beginClose must not return while an in-flight touch remains")
        let lateApproval = await registry.beginTouch(workflowID: "r-test")
        #expect(!lateApproval, "New touches should be rejected after transitioning to closing")
        await registry.endTouch(workflowID: "r-test")
        await closeTask.value
        #expect(closeDone.isSet)
        await registry.release(workflowID: "r-test")
        let gone = await registry.beginTouch(workflowID: "r-test")
        #expect(!gone, "Touches after release should be rejected")
    }
    
    @Test("Close finishes immediately when nothing is in flight")
    func beginCloseWithoutInflightReturnsImmediately() async {
        let registry = WorkRegistry()
        await registerOne(registry, span: nil)
        await registry.beginClose(workflowID: "r-test")
        await registry.release(workflowID: "r-test")
    }
    
    @Test("A finished run is not folded into an operator")
    func requireLiveRecordDoesNotFoldStaleIntoOperator() async throws {
        // Given
        let registry = WorkRegistry()

        // When
        let operatorRecord = try await registry.requireLiveRecord(workflowID: nil, context: "t")

        // Then
        #expect(operatorRecord == nil)
        await registerOne(registry, span: nil)
        let live = try await registry.requireLiveRecord(workflowID: "r-test", context: "t")
        #expect(live?.workflowID == "r-test")
        await registry.release(workflowID: "r-test")
        do {
            _ = try await registry.requireLiveRecord(workflowID: "r-test", context: "session.send")
            Issue.record("A stale run-scoped token should be rejected")
        } catch let error as TokenRejected {
            #expect(error.message.contains("finished run"), Comment(rawValue: error.message))
        }
    }
    
    // MARK: - Private
    private func registerOne(_ registry: WorkRegistry, span: String?) async {
        await registry.register(WorkRecord(
                workflowID: "r-test", workflowName: "response",
                principal: "cli:response", origin: .rpc,
                rootID: "t-abc", nodeID: span,
                correlator: nil, parameters: nil
        ))
    }
}
