//
//  TokenNamespace.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// The `token.*` methods and what each caller presents.
struct TokenNamespace: Sendable {
    // MARK: - Property
    let methods: [RPCMethod]

    // MARK: - Initializer
    init(
        authority: TokenAuthority
    ) {
        let issue = TokenIssueMethod(authority: authority)

        self.methods = [
            RPCMethod("token.issue", .unary(.token) { request, claims in
                JSONObject(try await issue.handle(request, claims: claims))
            })
        ]
    }

    // MARK: - Public
    // MARK: - Private
}
