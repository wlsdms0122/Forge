//
//  WorkflowCancelGateTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import Forge

@Suite("WorkflowCancelGate Tests")
struct WorkflowCancelGateTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("Cancel by an unauthorized principal is rejected")
    func cancelDeniedForUnauthorizedPrincipal() async throws {
        // Given
        let (method, authority) = try await seed()
        let attacker = authority.mint(TokenClaims(principal: "cli:attacker"))
        do {
            _ = try await method.handle(RPCRequest(
                    id: "x", method: "workflow.cancel",
                    params: ["token": .string(attacker), "run_id": "r1"]), claims: try #require(authority.verify(attacker)))

        // Then
            Issue.record("Run-control by an out-of-scope principal should be rejected")
        } catch {
            #expect(String(describing: error).contains("not allowed"), "Should be a policy denial: \(error)")
        }
    }
    
    @Test("An authorized principal can cancel")
    func cancelAllowedForAuthorizedPrincipal() async throws {
        // Given
        let (method, authority) = try await seed()
        let owner = authority.mint(TokenClaims(principal: "cli:owner"))
        let result = try await method.handle(RPCRequest(
                id: "x", method: "workflow.cancel",
                params: ["token": .string(owner), "run_id": "r1"]), claims: try #require(authority.verify(owner)))

        // Then
        #expect(result["cancelled"]?.boolValue == true, "A permitted principal should be able to cancel a run within its authority")
    }
    
    @Test("Cancelling an unknown run is a no-op, not an error")
    func cancelUnknownRunIsNoOpNotError() async throws {
        // Given
        let (method, authority) = try await seed()
        let attacker = authority.mint(TokenClaims(principal: "cli:attacker"))
        let result = try await method.handle(RPCRequest(
                id: "x", method: "workflow.cancel",
                params: ["token": .string(attacker), "run_id": "does-not-exist"]), claims: try #require(authority.verify(attacker)))

        // Then
        #expect(result["cancelled"]?.boolValue == false)
    }
    
    // MARK: - Private
    private func seed() async throws -> (WorkflowCancelMethod, TokenAuthority) {
        let pool = WorkflowPool(maximumConcurrentSteps: 1)
        try await pool.register(runID: "r1", workflowName: "<inline>",
            rootID: "r1",
            origin: .manual, principal: "cli:owner")
        let authority = TokenAuthority()
        let method = WorkflowCancelMethod(
            pool: pool, policyStore: PolicyStore(seed: ["cli:owner": ["<inline>"]]))
        
        return (method, authority)
    }
}
