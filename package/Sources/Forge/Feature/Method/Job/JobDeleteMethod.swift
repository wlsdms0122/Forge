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

    // MARK: - Initializer
    init(store: JobStore) {
        self.store = store
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        let id = try requireID(request.rawParams, "job.delete")
        try await store.delete(id: id)

        return ["id": id, "deleted": true]
    }

    // MARK: - Private
}
