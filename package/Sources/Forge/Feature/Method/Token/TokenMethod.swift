//
//  TokenMethod.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct TokenIssueMethod: Sendable {
    // MARK: - Property
    let authority: TokenAuthority
    
    // MARK: - Initializer
    init(authority: TokenAuthority) {
        self.authority = authority
    }
    
    // MARK: - Public
    static func isIssuable(_ principal: String) -> Bool {
        principal == "system:runner"
            || principal == "system:admin"
            || principal.hasPrefix("admin:")
    }
    
    static func isWellFormed(_ principal: String) -> Bool {
        if principal == "system:runner" || principal == "system:admin" { return true }
        
        guard principal.hasPrefix("admin:") else { return false }
        
        let user = principal.dropFirst("admin:".count)
        
        if user.isEmpty { return false }
        
        return user.allSatisfy { character in
            character.isASCII
                && (character.isLetter
                    || character.isNumber
                    || character == "_"
                    || character == "."
                    || character == "-")
        }
    }
    
    static func canIssue(presenter: String, requested: String) -> Bool {
        presenter == "system:admin" || presenter.hasPrefix("admin:")
    }
    
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        let claims = try authority.requireClaims(request.params)
        
        guard
            let principal = request.params["principal"] as? String,
            !principal.isEmpty
        else {
            throw ProtocolError("token.issue: 'principal' (string) required")
        }
        
        guard Self.isIssuable(principal) else {
            throw ProtocolError(
                "token.issue: principal '\(principal)' is not in the issuable set"
                    + " — see `forge token issue --help`"
            )
        }
        
        guard Self.isWellFormed(principal) else {
            throw ProtocolError(
                "token.issue: principal '\(principal)' is malformed"
                    + " — admin:<user> needs a non-empty [A-Za-z0-9_.-] user"
            )
        }
        
        guard Self.canIssue(presenter: claims.principal, requested: principal) else {
            throw ProtocolError(
                "token.issue: principal '\(claims.principal)' may not issue '\(principal)'"
                    + " — only admin-tier tokens can delegate"
            )
        }
        
        let token = authority.mint(TokenClaims(principal: principal, workflowID: nil))
        
        return ["token": token, "principal": principal]
    }
    
    // MARK: - Private
}
