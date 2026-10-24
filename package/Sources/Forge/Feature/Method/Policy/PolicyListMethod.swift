//
//  PolicyListMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct PolicyListMethod: Sendable {
    // MARK: - Property
    let store: PolicyStore

    // MARK: - Initializer
    init(store: PolicyStore) {
        self.store = store
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        let catalog = await store.catalog()
        let failureSummary: [[String: Any]] = catalog.failures.map { failure in
            [
                "path": failure.path,
                "reason": failure.reason,
                "mtime": ISO8601.string(failure.mtime),
            ]
        }

        return ["policy": catalog.policy, "failures": failureSummary]
    }

    // MARK: - Private
}
