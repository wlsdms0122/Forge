//
//  AsyncDispatchTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("AsyncDispatch Tests")
struct AsyncDispatchTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("Policy denial throws immediately even for async dispatch")
    func asyncPolicyDenialThrowsSynchronously() async throws {
        // Given
        let (method, authority) = try makeDeniedMethod()
        let token = authority.mint(TokenClaims(principal: "system:rpc"))
        let specJSON: [String: JSONValue] = [
            "failing": ["nonzero_exit", "timeout"],
            "body": [["let": "x", "value": ["call": ["procedure": "shell", "arguments": ["command": ["/bin/echo", "nope"]]]]]],
        ]
        do {
            _ = try await method.handle(RPCRequest(
                    id: "r-async-denied",
                    method: "workflow.dispatch",
                    params: ["token": .string(token), "spec": .object(specJSON), "async": true]
            ), claims: try #require(authority.verify(token)))

        // Then
            Issue.record("Policy denial should throw immediately even when async")
        } catch {
            #expect(String(describing: error).contains("not allowed"), "Rejection reason should be a policy denial: \(error)")
        }
    }
    
    @Test("Sync dispatch returns the completed result")
    func syncReturnsCompletedResult() async throws {
        // Given
        let (method, authority) = try makeMethod()
        let token = authority.mint(TokenClaims(principal: "system:rpc"))
        let specJSON: [String: JSONValue] = [
            "failing": ["nonzero_exit", "timeout"],
            "body": [
                ["let": "x", "value": ["call": ["procedure": "shell", "arguments": ["command": ["/bin/echo", "done"]]]]],
            ],
            "returns": "Dictionary<String, Any>",
            "result": ["dictionary": [["v", ["ref": "x"]]]],
        ]
        let result = try await method.handle(RPCRequest(
                id: "r-sync",
                method: "workflow.dispatch",
                params: ["token": .string(token), "spec": .object(specJSON), "async": false]
        ), claims: try #require(authority.verify(token)))

        // Then
        #expect(result["status"]?.stringValue == "ok")
        let output = result["output"]?.objectValue
        #expect(output?["v"] != nil)
    }
    
    @Test("Async dispatch returns immediately with running status")
    func asyncReturnsImmediatelyWithRunningStatus() async throws {
        // Given
        let (method, authority) = try makeMethod()
        let token = authority.mint(TokenClaims(principal: "system:rpc"))
        let specJSON: [String: JSONValue] = [
            "failing": ["nonzero_exit", "timeout"],
            "body": [
                ["let": "slow", "value": ["call": ["procedure": "shell", "arguments": ["command": ["/bin/sleep", "0.3"]]]]],
            ],
        ]
        // The library is read once a process; what is timed is the dispatch.
        _ = try ForgeVocabulary.shipped.get().frontend
        let startedAt = ContinuousClock.now
        let result = try await method.handle(RPCRequest(
                id: "r-async",
                method: "workflow.dispatch",
                params: ["token": .string(token), "spec": .object(specJSON), "async": true]
        ), claims: try #require(authority.verify(token)))
        let elapsedMs = (ContinuousClock.now - startedAt).milliseconds

        // Then
        #expect(elapsedMs < 100, "async=true should return before the workflow completes (actual: \(elapsedMs)ms)")
        #expect(result["status"]?.stringValue == "running")
        let runID = try #require(result["run_id"]?.stringValue)
        #expect(runID.hasPrefix("wf-"), "runID should be forge-minted (wf-*): \(runID)")
        #expect(runID != "r-async")
        try await Task.sleep(for: .milliseconds(500))
    }
    
    // MARK: - Private
    private func makeMethod() throws -> (WorkflowDispatchMethod, TokenAuthority) {
        try makeMethod(policy: ["*": ["*"]])
    }

    private func makeDeniedMethod() throws -> (WorkflowDispatchMethod, TokenAuthority) {
        try makeMethod(policy: ["system:other": ["*"]])
    }

    private func makeMethod(policy: [String: [String]]) throws -> (WorkflowDispatchMethod, TokenAuthority) {
        let catalog = try WorkflowCatalog(directory: nil)
        let bus = WorkflowEventBus()
        let authority = TokenAuthority()
        let runner = WorkflowRunner(catalog: catalog,
            eventBus: bus,
            policyStore: PolicyStore(seed: policy),
            pool: WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max),
            workRegistry: WorkRegistry(),
            tokenAuthority: authority,
            capabilities: CapabilitySet(
                shell: LiveShell(),
                agent: LiveAgent(executor: AgentExecutor(backend: StubBackend("noop"))),
                resources: LiveResources(store: ResourceStore(directory: nil))
            ))
        let method = WorkflowDispatchMethod(runner: runner, catalog: catalog,
            workRegistry: WorkRegistry())

        return (method, authority)
    }
}

