//
//  PolicyNamespace.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// The `policy.*` methods and what each caller presents.
struct PolicyNamespace: Sendable {
    // MARK: - Property
    let methods: [RPCMethod]

    // MARK: - Initializer
    init(
        store: PolicyStore
    ) {
        let list = PolicyListMethod(store: store)
        let check = PolicyCheckMethod(store: store)

        self.methods = [
            RPCMethod("policy.list", .unary(.token) { request, _ in
                JSONObject(try await list.handle(request))
            }),
            RPCMethod("policy.check", .unary(.token) { request, _ in
                JSONObject(try await check.handle(request))
            })
        ]
    }

    // MARK: - Public
    // MARK: - Private
}
