//
//  DispatchStreamTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("DispatchStream Tests")
struct DispatchStreamTests {
    private actor CollectingSink: EventSink {
        private var collected: [JSONObject] = []
        func emit(_ object: JSONObject) async { collected.append(object) }
        func snapshot() -> [JSONObject] { collected }
    }

    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("Streams events then emits a terminal result at the end")
    func streamsEventsThenTerminalResult() async throws {
        // Given
        let (method, authority, _) = makeMethod()
        let token = authority.mint(TokenClaims(principal: "system:rpc"))
        let sink = CollectingSink()
        let specJSON: [String: Any] = [
            "steps": [
                ["id": "one", "shell": ["command": ["/bin/echo", "a"]]],
                ["id": "two", "shell": ["command": ["/bin/echo", "b"]]],
            ],
            "outputs": ["v": ["ref": "two"]],
        ]
        try await method.handle(RPCRequest(
                id: "r-stream",
                method: "workflow.dispatch_stream",
                params: ["token": token, "spec": specJSON]
            ), sink: sink)
        let lines = (await sink.snapshot()).map { line in line.dict }

        // Then
        #expect(lines.count >= 3, "At least 3 lines: ack + events + terminal")
        let ack = lines[0]
        #expect(ack["id"] as? String == "r-stream")
        let ackResult = try #require(ack["result"] as? [String: Any])
        #expect(ackResult["status"] as? String == "streaming")
        let wfID = try #require(ackResult["workflow_id"] as? String)
        let events = lines.dropFirst().dropLast()
        for error in events {
            #expect(error["kind"] as? String == "workflow.event")
            #expect(error["workflow_id"] as? String == wfID)
        }

        let eventKinds = events.compactMap { event in event["event"] as? String }
        #expect(eventKinds.contains("workflow.started"))
        #expect(eventKinds.contains("step.started"))
        #expect(eventKinds.contains("step.completed"))
        #expect(eventKinds.contains("workflow.completed"))
        let stepStarts = events.filter { event in (event["event"] as? String) == "step.started" }
        .compactMap { line in line["step"] as? String }
        #expect(stepStarts == ["one", "two"])
        let terminal = try #require(lines.last)
        #expect(terminal["kind"] as? String == "workflow.result")
        let result = try #require(terminal["result"] as? [String: Any])
        #expect(result["status"] as? String == "ok")
        #expect(result["workflow_id"] as? String == wfID)
        #expect((result["outputs"] as? [String: Any])?["v"] != nil)
    }

    @Test("Policy denial throws before the ack")
    func policyDenialThrowsBeforeAck() async throws {
        // Given
        let (method, authority, _) = makeMethod(policySeed: ["system:other": ["*"]])
        let token = authority.mint(TokenClaims(principal: "system:rpc"))
        let sink = CollectingSink()
        let specJSON: [String: Any] = [
            "steps": [["id": "x", "shell": ["command": ["/bin/echo", "nope"]]]],
        ]
        do {
            try await method.handle(RPCRequest(
                    id: "r-denied",
                    method: "workflow.dispatch_stream",
                    params: ["token": token, "spec": specJSON]
                ), sink: sink)

        // Then
            Issue.record("Policy denial should throw")
        } catch {
            #expect(String(describing: error).contains("not allowed"))
        }

        let lines = (await sink.snapshot()).map { line in line.dict }
        #expect(lines.isEmpty, "No stream lines should be emitted on denial: \(lines)")
    }

    @Test("Filters out foreign-node events even under the same root")
    func sameRootForeignNodeEventsFiltered() async throws {
        // Given
        let (method, authority, bus) = makeMethod()
        let token = authority.mint(TokenClaims(principal: "system:rpc"))
        let sink = CollectingSink()
        let specJSON: [String: Any] = [
            "steps": [["id": "slow", "shell": ["command": ["/bin/sleep", "0.3"]]]],
        ]
        let handleTask = Task {
            try await method.handle(RPCRequest(
                    id: "r-subtree",
                    method: "workflow.dispatch_stream",
                    params: ["token": token, "spec": specJSON]
                ), sink: sink)
        }

        var wfID: String?
        for _ in 0..<100 {
            if let ack = (await sink.snapshot()).first?.dict,
            let payload = ack["result"] as? [String: Any],
            let identifier = payload["workflow_id"] as? String { wfID = identifier; break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        // Then
        let rootID = try #require(wfID)
        await bus.publish(WorkflowEvent(
                kind: .stepStarted, workflowID: "intruder-run", workflowName: "intruder",
                stepID: "evil", rootID: rootID, parentRunID: "someone-elses-run"))
        await bus.publish(WorkflowEvent(
                kind: .workflowStarted, workflowID: "child-run", workflowName: "child",
                rootID: rootID, parentRunID: rootID))
        await bus.publish(WorkflowEvent(
                kind: .stepStarted, workflowID: "grandchild-run", workflowName: "grandchild",
                stepID: "gs", rootID: rootID, parentRunID: "child-run"))
        try await handleTask.value
        let lines = (await sink.snapshot()).map { line in line.dict }
        let leaked = lines.filter { line in (line["workflow_id"] as? String) == "intruder-run" }
        #expect(leaked.isEmpty, "Events from outside the subtree leaked despite sharing the root: \(leaked)")
        let relayedIDs = Set(lines.compactMap { line in line["workflow_id"] as? String })
        #expect(relayedIDs.contains("child-run"), "Child run events should flow through: \(relayedIDs)")
        #expect(relayedIDs.contains("grandchild-run"), "Grandchild runs should flow through the chain too: \(relayedIDs)")
        let ownKinds = lines.compactMap { line in line["event"] as? String }
        #expect(ownKinds.contains("workflow.completed"), "The run's own events should flow through: \(ownKinds)")
    }

    @Test("Unawaited runs are computed from the async edge")
    func unawaitedComputedFromAsyncEdge() async throws {
        // Given
        let (method, authority, bus) = makeMethod()
        let token = authority.mint(TokenClaims(principal: "system:rpc"))
        let sink = CollectingSink()
        let specJSON: [String: Any] = [
            "steps": [["id": "slow", "shell": ["command": ["/bin/sleep", "0.3"]]]],
        ]
        let handleTask = Task {
            try await method.handle(RPCRequest(
                    id: "r-detached",
                    method: "workflow.dispatch_stream",
                    params: ["token": token, "spec": specJSON]
                ), sink: sink)
        }

        var wfID: String?
        for _ in 0..<100 {
            if let ack = (await sink.snapshot()).first?.dict,
            let payload = ack["result"] as? [String: Any],
            let identifier = payload["workflow_id"] as? String { wfID = identifier; break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        // Then
        let rootID = try #require(wfID)
        await bus.publish(WorkflowEvent(
                kind: .workflowStarted, workflowID: "job-run", workflowName: "worker",
                rootID: rootID, parentRunID: rootID, asyncDispatch: true))
        await bus.publish(WorkflowEvent(
                kind: .stepStarted, workflowID: "job-child", workflowName: "bot-invoke",
                stepID: "boot", rootID: rootID, parentRunID: "job-run"))
        await bus.publish(WorkflowEvent(
                kind: .workflowStarted, workflowID: "sync-child", workflowName: "capture",
                rootID: rootID, parentRunID: rootID))
        try await handleTask.value
        let lines = (await sink.snapshot()).map { line in line.dict }
        func unawaitedFlag(_ id: String) -> Bool? {
            lines.first { line in (line["workflow_id"] as? String) == id }?["unawaited"] as? Bool
        }
        #expect(lines.first { line in (line["workflow_id"] as? String) == "job-run" } != nil, "Unawaited children are still in the lineage subtree — the relay does not filter them")
        #expect(unawaitedFlag("job-run") == true, "Run that crossed an async edge")
        #expect(unawaitedFlag("job-child") == true, "The root does not wait for sync grandchildren below it either")
        #expect(unawaitedFlag("sync-child") == nil, "The root waits for sync children — no flag")
        #expect(unawaitedFlag(rootID) == nil, "The root itself is not unawaited")
    }

    @Test("Async dispatch marks the run as async")
    func asyncDispatchMarksRunAsync() async throws {
        // Given
        let store = SpecCatalog(directory: nil, loader: ForgeSpec.loader())
        let bus = WorkflowEventBus()
        let authority = TokenAuthority()
        let registry = WorkRegistry()
        let runner = SpecWorkflowRunner(
            catalog: store,
            eventBus: bus,
            policyStore: PolicyStore(seed: ["*": ["*"]]),
            pool: WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max),
            workRegistry: registry,
            tokenAuthority: authority,
            shell: LiveShell(),
            agent: LiveAgent(executor: Executor(backend: StubBackend("noop"))),
            resources: LiveResources(store: ResourceStore(directory: nil)))
        let dispatchMethod = WorkflowDispatchMethod(runner: runner, store: store,
            workRegistry: registry,
            tokenAuthority: authority)
        let (_, stream) = await bus.subscribe()
        let token = authority.mint(TokenClaims(principal: "system:rpc"))
        let specJSON: [String: Any] = [
            "steps": [["id": "one", "shell": ["command": ["/bin/echo", "a"]]]],
        ]
        let ack = try await dispatchMethod.handle(RPCRequest(
                id: "r-async", method: "workflow.dispatch",
                params: ["token": token, "spec": specJSON, "async": true]
        ))

        // Then
        #expect(ack.dict["status"] as? String == "running")
        var sawCompleted = false
        for await event in stream {
            #expect(event.asyncDispatch, "Events from an async run should carry that fact: \(event.kind)")
            if event.kind == .workflowCompleted { sawCompleted = true; break }
        }
        #expect(sawCompleted)
    }

    @Test("A failed run emits a failed terminal event")
    func failedRunEmitsFailedTerminal() async throws {
        // Given
        let (method, authority, _) = makeMethod()
        let token = authority.mint(TokenClaims(principal: "system:rpc"))
        let sink = CollectingSink()
        let specJSON: [String: Any] = [
            "steps": [["id": "boom", "shell": ["command": ["/usr/bin/false"]]]],
        ]
        try await method.handle(RPCRequest(
                id: "r-fail",
                method: "workflow.dispatch_stream",
                params: ["token": token, "spec": specJSON]
            ), sink: sink)
        let lines = (await sink.snapshot()).map { line in line.dict }

        // Then
        let terminal = try #require(lines.last)
        #expect(terminal["kind"] as? String == "workflow.result")
        let result = try #require(terminal["result"] as? [String: Any])
        #expect(result["status"] as? String == "failed")
        #expect(result["error"] != nil)
        let eventKinds = lines.dropFirst().dropLast().compactMap { line in line["event"] as? String }
        #expect(eventKinds.contains("step.failed") || eventKinds.contains("workflow.failed"), "Failure events should be carried on the stream: \(eventKinds)")
    }

    @Test("The terminal event preserves the failure type instead of flattening it")
    func streamTerminalPreservesFailureType() async throws {
        // Given
        let store = SpecCatalog(directory: nil, loader: ForgeSpec.loader())
        let bus = WorkflowEventBus()
        let pool = WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: 1)
        try await pool.register(workflowID: "occupier", workflowName: "other", rootID: "occupier",
            origin: .manual, principal: "t")
        let authority = TokenAuthority()
        let registry = WorkRegistry()
        let runner = SpecWorkflowRunner(
            catalog: store,
            eventBus: bus,
            policyStore: PolicyStore(seed: ["*": ["*"]]),
            pool: pool,
            workRegistry: registry,
            tokenAuthority: authority,
            shell: LiveShell(),
            agent: LiveAgent(executor: Executor(backend: StubBackend("stub"))),
            resources: LiveResources(store: ResourceStore(directory: nil)))
        let dispatchMethod = WorkflowDispatchMethod(runner: runner, store: store,
            workRegistry: registry,
            tokenAuthority: authority)
        let method = WorkflowDispatchStreamMethod(dispatchMethod: dispatchMethod, eventBus: bus)
        let token = authority.mint(TokenClaims(principal: "system:rpc"))
        let sink = CollectingSink()
        try await method.handle(RPCRequest(
                id: "r-cap",
                method: "workflow.dispatch_stream",
                params: ["token": token,
                    "spec": ["steps": [["id": "x", "shell": ["command": ["/bin/echo", "hi"]]]]]]
            ), sink: sink)
        let lines = (await sink.snapshot()).map { line in line.dict }

        // Then
        let terminal = try #require(lines.last)
        #expect(terminal["kind"] as? String == "workflow.result")
        let result = try #require(terminal["result"] as? [String: Any])
        #expect(result["status"] as? String == "failed")
        let error = try #require(result["error"] as? [String: Any])
        #expect(error["type"] as? String == "RunCapExceeded", "The terminal carries the actual failure type: \(error)")
    }

    // MARK: - Private
    private func makeMethod(policySeed: [String: [String]] = ["*": ["*"]])

    -> (WorkflowDispatchStreamMethod, TokenAuthority, WorkflowEventBus)

    {
        let store = SpecCatalog(directory: nil, loader: ForgeSpec.loader())
        let bus = WorkflowEventBus()
        let authority = TokenAuthority()
        let registry = WorkRegistry()
        let runner = SpecWorkflowRunner(
            catalog: store,
            eventBus: bus,
            policyStore: PolicyStore(seed: policySeed),
            pool: WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max),
            workRegistry: registry,
            tokenAuthority: authority,
            shell: LiveShell(),
            agent: LiveAgent(executor: Executor(backend: StubBackend("noop"))),
            resources: LiveResources(store: ResourceStore(directory: nil)))
        let dispatchMethod = WorkflowDispatchMethod(runner: runner, store: store,
            workRegistry: registry,
            tokenAuthority: authority)
        let method = WorkflowDispatchStreamMethod(dispatchMethod: dispatchMethod, eventBus: bus)

        return (method, authority, bus)
    }
}
