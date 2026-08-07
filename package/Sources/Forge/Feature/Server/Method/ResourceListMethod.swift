//
//  ResourceListMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ResourceListMethod: Sendable {
    // MARK: - Property
    let store: ResourceStore
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(store: ResourceStore, tokenAuthority: TokenAuthority) {
        self.store = store
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        _ = try tokenAuthority.requireClaims(request.params)

        let entries = await store.all()
        let rows: [[String: Any]] = entries.map { entry in
            [
                "path": entry.path,
                "size": entry.size,
                "mtime": ISO8601.string(entry.mtime)
            ]
        }

        return ["resources": rows]
    }

    // MARK: - Private
}
