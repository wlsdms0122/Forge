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
    
    // MARK: - Private
}
