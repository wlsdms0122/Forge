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
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        guard let id = request.params["id"]?.stringValue, !id.isEmpty else {
            throw ProtocolError("job.delete: 'id' (string) required")
        }

        try await store.delete(id: id)

        return ["id": .string(id), "deleted": true]
    }

    // MARK: - Private
}
