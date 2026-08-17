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
        let (method, authority) = makeDeniedMethod()
        let token = authority.mint(TokenClaims(principal: "system:rpc"))
        let specJSON: [String: Any] = [
            "body": [["id": "x", "shell": ["command": ["/bin/echo", "nope"]]]],
        ]
        do {
            _ = try await method.handle(RPCRequest(
                    id: "r-async-denied",
                    method: "workflow.dispatch",
                    params: ["token": token, "spec": specJSON, "async": true]
            ))

        // Then
            Issue.record("Policy denial should throw immediately even when async")
        } catch {
            #expect(String(describing: error).contains("not allowed"), "Rejection reason should be a policy denial: \(error)")
        }
    }
    
    @Test("Sync dispatch returns the completed result")
    func syncReturnsCompletedResult() async throws {
        // Given
        let (method, authority) = makeMethod()
        let token = authority.mint(TokenClaims(principal: "system:rpc"))
        let specJSON: [String: Any] = [
            "body": [
                ["id": "x",
                    "shell": ["command": ["/bin/echo", "done"]]],
            ],
            "result": ["v": ["ref": "x"]],
        ]
        let result = try await method.handle(RPCRequest(
                id: "r-sync",
                method: "workflow.dispatch",
                params: ["token": token, "spec": specJSON, "async": false]
        ))

        // Then
        #expect(result.dict["status"] as? String == "ok")
        let outputs = result.dict["outputs"] as? [String: Any]
        #expect(outputs?["v"] != nil)
    }
    
    @Test("Async dispatch returns immediately with running status")
    func asyncReturnsImmediatelyWithRunningStatus() async throws {
        // Given
        let (method, authority) = makeMethod()
        let token = authority.mint(TokenClaims(principal: "system:rpc"))
        let specJSON: [String: Any] = [
            "body": [
                ["id": "slow",
                    "shell": ["command": ["/bin/sleep", "0.3"]]],
            ],
        ]
        let startedAt = ContinuousClock.now
        let result = try await method.handle(RPCRequest(
                id: "r-async",
                method: "workflow.dispatch",
                params: ["token": token, "spec": specJSON, "async": true]
        ))
        let elapsedMs = (ContinuousClock.now - startedAt).milliseconds

        // Then
        #expect(elapsedMs < 100, "async=true should return before the workflow completes (actual: \(elapsedMs)ms)")
        #expect(result.dict["status"] as? String == "running")
        let wfID = try #require(result.dict["workflow_id"] as? String)
        #expect(wfID.hasPrefix("wf-"), "runID should be forge-minted (wf-*): \(wfID)")
        #expect(wfID != "r-async")
        try await Task.sleep(for: .milliseconds(500))
    }
    
    // MARK: - Private
    private func makeMethod() -> (WorkflowDispatchMethod, TokenAuthority) {
        makeMethod(policy: ["*": ["*"]])
    }

    private func makeDeniedMethod() -> (WorkflowDispatchMethod, TokenAuthority) {
        makeMethod(policy: ["system:other": ["*"]])
    }

    private func makeMethod(policy: [String: [String]]) -> (WorkflowDispatchMethod, TokenAuthority) {
        let store = SpecCatalog(directory: nil, loader: ForgeSpec.loader())
        let bus = WorkflowEventBus()
        let authority = TokenAuthority()
        let runner = SpecWorkflowRunner(catalog: store,
            eventBus: bus,
            policyStore: PolicyStore(seed: policy),
            pool: WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max),
            workRegistry: WorkRegistry(),
            tokenAuthority: authority,
            shell: LiveShell(),
            agent: LiveAgent(executor: Executor(backend: StubBackend("noop"))),
            resources: LiveResources(store: ResourceStore(directory: nil)))
        let method = WorkflowDispatchMethod(runner: runner, store: store,
            workRegistry: WorkRegistry(), tokenAuthority: authority)

        return (method, authority)
    }
}

