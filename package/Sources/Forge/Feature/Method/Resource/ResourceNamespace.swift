//
//  ResourceNamespace.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// The `resource.*` methods and what each caller presents.
struct ResourceNamespace: Sendable {
    // MARK: - Property
    let methods: [RPCMethod]

    // MARK: - Initializer
    init(
        store: ResourceStore
    ) {
        let list = ResourceListMethod(store: store)
        let read = ResourceReadMethod(store: store)

        self.methods = [
            RPCMethod("resource.list", .unary(.token) { request, _ in
                try await list.handle(request)
            }),
            RPCMethod("resource.read", .unary(.token) { request, _ in
                try await read.handle(request)
            })
        ]
    }

    // MARK: - Public
    // MARK: - Private
}
