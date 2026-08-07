//
//  TokenAuthority.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import CryptoKit

struct TokenAuthority: Sendable {
    // MARK: - Property
    private let seed: SymmetricKey
    
    // MARK: - Initializer
    init() {
        self.seed = SymmetricKey(size: .bits256)
    }
    
    // MARK: - Public
    func mint(_ claims: TokenClaims) -> String {
        let payload = (try? JSONEncoder().encode(claims)) ?? Data()
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: seed)
        
        return payload.base64EncodedString() + "." + Data(mac).base64EncodedString()
    }
    
    func verify(_ token: String) -> TokenClaims? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        
        guard
            parts.count == 2,
            let payload = Data(base64Encoded: String(parts[0])),
            let mac = Data(base64Encoded: String(parts[1]))
        else {
            return nil
        }
        
        guard
            HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: payload, using: seed)
        else {
            return nil
        }
        
        return try? JSONDecoder().decode(TokenClaims.self, from: payload)
    }
    
    func requireClaims(_ params: [String: Any]) throws -> TokenClaims {
        guard let token = params["token"] as? String, !token.isEmpty else {
            throw ProtocolError("'token' (string) required — issue one with `forge token issue`")
        }
        
        guard let claims = verify(token) else {
            throw TokenRejected(
                "token verification failed — signature does not match this daemon's seed"
                    + " (reissue required)"
            )
        }
        
        return claims
    }
    
    func requireOperatorClaims(_ params: [String: Any], method: String) throws -> TokenClaims {
        let claims = try requireClaims(params)
        
        guard !claims.principal.hasPrefix("cli:") else {
            throw ProtocolError(
                "\(method): a workflow subprocess token cannot perform this operator action"
                    + " — use an operator/service token"
            )
        }
        
        return claims
    }
    
    // MARK: - Private
}
