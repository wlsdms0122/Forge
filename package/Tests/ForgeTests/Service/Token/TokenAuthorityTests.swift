//
//  TokenAuthorityTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import Forge

@Suite("TokenAuthority Tests")
struct TokenAuthorityTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("A minted token verifies with the same claims")
    func mintVerifyRoundTrip() {
        // Given
        let authority = TokenAuthority()
        let token = authority.mint(TokenClaims(principal: "cli:response", workflowID: "wf-1"))
        let claims = authority.verify(token)

        // Then
        #expect(claims?.principal == "cli:response")
        #expect(claims?.workflowID == "wf-1")
    }
    
    @Test("An operator token has no workflow binding")
    func operatorTokenHasNoWorkflowID() {
        // Given
        let authority = TokenAuthority()
        let token = authority.mint(TokenClaims(principal: "system:admin"))
        let claims = authority.verify(token)

        // Then
        #expect(claims?.principal == "system:admin")
        #expect(claims?.workflowID == nil)
    }
    
    @Test("A token signed with a different seed is rejected")
    func differentSeedRejectsToken() {
        // Given
        let firstAuthority = TokenAuthority()
        let secondAuthority = TokenAuthority()
        let token = firstAuthority.mint(TokenClaims(principal: "system:runner"))

        // Then
        #expect(secondAuthority.verify(token) == nil, "a token signed with a different seed must be rejected")
    }
    
    @Test("A token with a tampered payload is rejected")
    func tamperedPayloadRejected() {
        // Given
        let authority = TokenAuthority()
        let token = authority.mint(TokenClaims(principal: "cli:response", workflowID: "wf-1"))
        let forged = (try? JSONEncoder().encode(TokenClaims(principal: "system:admin")))?
        .base64EncodedString() ?? ""
        let sig = token.split(separator: ".").last.map(String.init) ?? ""

        // Then
        #expect(authority.verify(forged + "." + sig) == nil, "a token with a modified payload must be rejected — an LLM cannot forge the principal")
    }
    
    @Test("A token that is not even the right shape is rejected")
    func garbageTokenRejected() {
        // Given
        let authority = TokenAuthority()

        // Then
        #expect(authority.verify("not-a-token") == nil)
        #expect(authority.verify("") == nil)
        #expect(authority.verify("a.b.c") == nil)
    }
    
    @Test("The list of who may issue whom")
    func issuablePrincipals() {
        #expect(TokenIssueMethod.isIssuable("system:runner"))
        #expect(TokenIssueMethod.isIssuable("system:admin"))
        #expect(TokenIssueMethod.isIssuable("admin:jineun"))
        #expect(!TokenIssueMethod.isIssuable("cli:response"))
        #expect(!TokenIssueMethod.isIssuable("system:schedule:x"))
        #expect(!TokenIssueMethod.isIssuable("system:rpc"))
    }
    
    @Test("Issuance is only possible in the attenuating direction")
    func canIssueAttenuation() {
        #expect(TokenIssueMethod.canIssue(presenter: "system:admin", requested: "system:runner"))
        #expect(TokenIssueMethod.canIssue(presenter: "system:admin", requested: "admin:jineun"))
        #expect(TokenIssueMethod.canIssue(presenter: "admin:jineun", requested: "admin:other"))
        #expect(!TokenIssueMethod.canIssue(presenter: "cli:response", requested: "system:admin"))
        #expect(!TokenIssueMethod.canIssue(presenter: "cli:response", requested: "system:runner"))
        #expect(!TokenIssueMethod.canIssue(presenter: "service:slack", requested: "system:runner"))
        #expect(!TokenIssueMethod.canIssue(presenter: "system:runner", requested: "system:admin"))
        #expect(!TokenIssueMethod.canIssue(presenter: "system:schedule:x", requested: "system:admin"))
    }
    
    @Test("A principal must have the prescribed shape")
    func wellFormedPrincipal() {
        #expect(TokenIssueMethod.isWellFormed("system:admin"))
        #expect(TokenIssueMethod.isWellFormed("system:runner"))
        #expect(TokenIssueMethod.isWellFormed("admin:jineun"))
        #expect(TokenIssueMethod.isWellFormed("admin:user_1.2-x"))
        #expect(!TokenIssueMethod.isWellFormed("admin:"))
        #expect(!TokenIssueMethod.isWellFormed("admin:*"))
        #expect(!TokenIssueMethod.isWellFormed("admin:a b"))
        #expect(!TokenIssueMethod.isWellFormed("admin:a\nb"))
        #expect(!TokenIssueMethod.isWellFormed("cli:response"))
    }
    
    @Test("A malformed admin request is rejected")
    func issueRejectsMalformedAdmin() async {
        // Given
        let authority = TokenAuthority()
        let adminToken = authority.mint(TokenClaims(principal: "system:admin"))
        let method = TokenIssueMethod(authority: authority)
        let request = RPCRequest(id: "1", method: "token.issue",
            params: ["token": adminToken, "principal": "admin:*"])
        do {

        // When
            _ = try await method.handle(request)

        // Then
            Issue.record("issuing admin:* must be rejected at the format gate")
        } catch {}
    }
    
    @Test("An issue request without a token is rejected")
    func issueRejectsMissingToken() async {
        // Given
        let method = TokenIssueMethod(authority: TokenAuthority())
        let request = RPCRequest(id: "1", method: "token.issue", params: ["principal": "system:admin"])
        do {

        // When
            _ = try await method.handle(request)

        // Then
            Issue.record("token.issue without a token must be rejected")
        } catch {}
    }
    
    @Test("Issuance where the cli surface escalates its own privileges is rejected")
    func issueRejectsCliPresenterEscalation() async {
        // Given
        let authority = TokenAuthority()
        let cliToken = authority.mint(TokenClaims(principal: "cli:response", workflowID: "wf-1"))
        let method = TokenIssueMethod(authority: authority)
        let request = RPCRequest(id: "1", method: "token.issue",
            params: ["token": cliToken, "principal": "system:admin"])
        do {

        // When
            _ = try await method.handle(request)

        // Then
            Issue.record("admin issuance by a cli:* presenter must be rejected")
        } catch {}
    }
    
    @Test("Admin can delegate runner privileges")
    func issueAdminDelegatesRunner() async throws {
        // Given
        let authority = TokenAuthority()
        let adminToken = authority.mint(TokenClaims(principal: "system:admin"))
        let method = TokenIssueMethod(authority: authority)
        let request = RPCRequest(id: "1", method: "token.issue",
            params: ["token": adminToken, "principal": "system:runner"])
        let output = try await method.handle(request)
        let issued = output.dict["token"] as? String

        // Then
        #expect(authority.verify(issued ?? "")?.principal == "system:runner")
    }
    
    // MARK: - Private
}
