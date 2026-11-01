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
        workingDirectory: WorkingDirectory
    ) {
        let list = ResourceListMethod(workingDirectory: workingDirectory)
        let read = ResourceReadMethod(workingDirectory: workingDirectory)

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
