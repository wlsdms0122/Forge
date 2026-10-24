//
//  DaemonNamespace.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// The `daemon.*` methods and what each caller presents.
struct DaemonNamespace: Sendable {
    // MARK: - Property
    let methods: [RPCMethod]

    // MARK: - Initializer
    init(status: DaemonStatusMethod) {
        self.methods = [
            RPCMethod("daemon.status", .open { request in
                try await status.handle(request)
            })
        ]
    }

    // MARK: - Public
    // MARK: - Private
}
