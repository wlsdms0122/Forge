//
//  DispatchServiceTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/25/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("DispatchService Tests")
struct DispatchServiceTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("A method that takes a token refuses a call without one")
    func tokenRequired() async throws {
        // Given
        let authority = TokenAuthority()
        let sut = DispatchService(methods: TokenNamespace(authority: authority).methods, authority: authority)

        // When
        let error = await #expect(throws: ProtocolError.self) {
            _ = try await sut.dispatch(Self.request("token.issue", ["principal": "system:runner"]))
        }

        // Then
        #expect(error?.message.contains("'token' (string) required") == true)
    }

    @Test("A token another daemon minted is rejected")
    func foreignTokenRejected() async throws {
        // Given
        let authority = TokenAuthority()
        let sut = DispatchService(methods: TokenNamespace(authority: authority).methods, authority: authority)
        let foreign = TokenAuthority().mint(TokenClaims(principal: "system:admin"))

        // When / Then
        await #expect(throws: TokenRejected.self) {
            _ = try await sut.dispatch(
                Self.request("token.issue", ["token": foreign, "principal": "system:runner"])
            )
        }
    }

    @Test("A run's token cannot call an operator method")
    func operatorRefusesRunToken() async throws {
        // Given
        let authority = TokenAuthority()
        let sut = Self.session(authority)
        let run = authority.mint(TokenClaims(principal: "cli:response", workflowID: "wf-1"))

        // When
        let error = await #expect(throws: ProtocolError.self) {
            _ = try await sut.dispatch(Self.ack(token: run))
        }

        // Then
        #expect(error?.message.contains("operator action") == true)
    }

    @Test("An operator token calls an operator method")
    func operatorAcceptsOperatorToken() async throws {
        // Given
        let authority = TokenAuthority()
        let sut = Self.session(authority)

        for principal in ["system:admin", "system:runner", "admin:jineun"] {
            let token = authority.mint(TokenClaims(principal: principal))

            // When
            let result = try await sut.dispatch(Self.ack(token: token))

            // Then
            #expect(result.dict["ok"] as? Bool == true, "\(principal) should pass the gate")
        }
    }

    @Test("An open method answers without a token")
    func openNeedsNoToken() async throws {
        // Given
        let sut = DispatchService(
            methods: [RPCMethod("daemon.ping", .open { _ in ["pong": true] })],
            authority: TokenAuthority()
        )

        // When
        let result = try await sut.dispatch(Self.request("daemon.ping", [:]))

        // Then
        #expect(result.dict["pong"] as? Bool == true)
    }

    // MARK: - Public
    // MARK: - Private
    private static func session(_ authority: TokenAuthority) -> DispatchService {
        DispatchService(
            methods: SessionNamespace(
                handlerBus: WorkflowHandlerBus(),
                workRegistry: WorkRegistry()
            ).methods,
            authority: authority
        )
    }

    private static func ack(token: String) -> RPCRequest {
        request("session.handler.ack", [
            "token": token,
            "service": "slack",
            "message_id": "m1",
            "result": [String: Any]()
        ])
    }

    private static func request(_ method: String, _ params: [String: Any]) -> RPCRequest {
        RPCRequest(id: "1", method: method, params: params)
    }
}
