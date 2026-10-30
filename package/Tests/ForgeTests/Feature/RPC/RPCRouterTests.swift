//
//  RPCRouterTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/25/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("RPCRouter Tests")
struct RPCRouterTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("A method that takes a token refuses a call without one")
    func tokenRequired() async throws {
        // Given
        let authority = TokenAuthority()
        let sut = RPCRouter(methods: TokenNamespace(authority: authority).methods, authority: authority)

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
        let sut = RPCRouter(methods: TokenNamespace(authority: authority).methods, authority: authority)
        let foreign = TokenAuthority().mint(TokenClaims(principal: "system:admin"))

        // When / Then
        await #expect(throws: TokenRejected.self) {
            _ = try await sut.dispatch(
                Self.request("token.issue", ["token": .string(foreign), "principal": "system:runner"])
            )
        }
    }

    @Test("A run's token cannot call an operator method")
    func operatorRefusesRunToken() async throws {
        // Given
        let authority = TokenAuthority()
        let sut = Self.router(authority)
        let run = authority.mint(TokenClaims(principal: "cli:response", runID: "wf-1"))

        // When
        let error = await #expect(throws: ProtocolError.self) {
            _ = try await sut.dispatch(Self.operatorCall(token: run))
        }

        // Then
        #expect(error?.message.contains("operator action") == true)
    }

    @Test("An operator token calls an operator method")
    func operatorAcceptsOperatorToken() async throws {
        // Given
        let authority = TokenAuthority()
        let sut = Self.router(authority)

        for principal in ["system:admin", "system:runner", "admin:jineun"] {
            let token = authority.mint(TokenClaims(principal: principal))

            // When
            let result = try await sut.dispatch(Self.operatorCall(token: token))

            // Then
            #expect(result["ok"]?.boolValue == true, "\(principal) should pass the gate")
        }
    }

    @Test("An open method answers without a token")
    func openNeedsNoToken() async throws {
        // Given
        let sut = RPCRouter(
            methods: [RPCMethod("daemon.ping", .open { _ in ["pong": true] })],
            authority: TokenAuthority()
        )

        // When
        let result = try await sut.dispatch(Self.request("daemon.ping", [:]))

        // Then
        #expect(result["pong"]?.boolValue == true)
    }

    // MARK: - Public
    // MARK: - Private
    private static func router(_ authority: TokenAuthority) -> RPCRouter {
        RPCRouter(
            methods: [RPCMethod("test.operator", .unary(.operator) { _, _ in ["ok": true] })],
            authority: authority
        )
    }

    private static func operatorCall(token: String) -> RPCRequest {
        request("test.operator", ["token": .string(token)])
    }

    private static func request(_ method: String, _ params: [String: JSONValue]) -> RPCRequest {
        RPCRequest(id: "1", method: method, params: params)
    }
}
