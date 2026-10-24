//
//  OperatorGateTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import Forge

@Suite("OperatorGate Tests")
struct OperatorGateTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("A cli token cannot enter where an operator is required")
    func requireOperatorClaimsRejectsCliToken() throws {
        // Given
        let authority = TokenAuthority()
        let cli = authority.mint(TokenClaims(principal: "cli:response", workflowID: "wf-1"))

        // Then
        let error = try #require(throws: (any Error).self) {
            try authority.requireOperatorClaims(["token": cli], method: "service.run")
        }
        
        #expect(String(describing: error).contains("operator action"), "Should be a cli: rejection reason: \(error)")
    }
    
    @Test("An operator token passes")
    func requireOperatorClaimsAcceptsOperator() throws {
        // Given
        let authority = TokenAuthority()
        for principal in ["system:admin", "system:runner", "admin:jineun"] {
            let token = authority.mint(TokenClaims(principal: principal))

        // When
            let claims = try authority.requireOperatorClaims(["token": token], method: "service.run")

        // Then
            #expect(claims.principal == principal)
        }
    }
    
    @Test("Session handler ack also rejects cli tokens")
    func sessionHandlerAckRejectsCliToken() async throws {
        // Given
        let authority = TokenAuthority()
        let ack = SessionHandlerAckMethod(handlerBus: WorkflowHandlerBus(), tokenAuthority: authority)
        let cli = authority.mint(TokenClaims(principal: "cli:response", workflowID: "wf-1"))
        do {
            _ = try await ack.handle(RPCRequest(
                    id: "a", method: "session.handler.ack",
                    params: ["token": cli, "service": "slack", "message_id": "m1", "result": [String: Any]()]))

        // Then
            Issue.record("An ack with a cli: token should be rejected")
        } catch {
            #expect(String(describing: error).contains("operator action"), "Should be an operator-gate rejection: \(error)")
        }
    }
    
    @Test("An operator token can ack")
    func sessionHandlerAckAllowsOperatorToken() async throws {
        // Given
        let authority = TokenAuthority()
        let ack = SessionHandlerAckMethod(handlerBus: WorkflowHandlerBus(), tokenAuthority: authority)
        let operatorToken = authority.mint(TokenClaims(principal: "system:runner"))
        let result = try await ack.handle(RPCRequest(
                id: "a", method: "session.handler.ack",
                params: ["token": operatorToken, "service": "slack", "message_id": "m1", "result": [String: Any]()]))

        // Then
        #expect(result.dict["ok"] as? Bool == true, "An operator token should pass the gate")
    }
    
    // MARK: - Private
}
