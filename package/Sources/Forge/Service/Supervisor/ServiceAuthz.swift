//
//  ServiceAuthz.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum ServiceAuthz {
    static func requireActingAs(
        _ service: String,
        claims: TokenClaims,
        method: String
    ) throws {
        guard claims.principal.hasPrefix("service:") else { return }
        
        let owned = String(claims.principal.dropFirst("service:".count))
        
        guard owned == service else {
            throw ProtocolError(
                "\(method): token principal '\(claims.principal)' may not act as service '\(service)'"
            )
        }
    }
    
    static func requireGlobal(claims: TokenClaims, method: String) throws {
        guard !claims.principal.hasPrefix("service:") else {
            throw ProtocolError(
                "\(method): a service token cannot perform global service control — use an operator token"
            )
        }
    }
}
