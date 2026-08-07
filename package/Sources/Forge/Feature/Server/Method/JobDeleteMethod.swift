//
//  JobDeleteMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct JobDeleteMethod: Sendable {
    // MARK: - Property
    let store: JobStore
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(store: JobStore, tokenAuthority: TokenAuthority) {
        self.store = store
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        _ = try tokenAuthority.requireClaims(request.params)

        let id = try requireID(request.params, "job.delete")
        try await store.delete(id: id)

        return ["id": id, "deleted": true]
    }

    // MARK: - Private
}
