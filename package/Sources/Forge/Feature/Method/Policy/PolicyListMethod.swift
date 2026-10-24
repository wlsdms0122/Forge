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
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        let catalog = await store.catalog()
        let policy = catalog.policy.mapValues { workflows in JSONValue.array(workflows.map(JSONValue.string)) }
        let failureSummary: [JSONValue] = catalog.failures.map { failure in
            [
                "path": .string(failure.path),
                "reason": .string(failure.reason),
                "mtime": .string(ISO8601.string(failure.mtime))
            ]
        }
        
        return ["policy": .object(policy), "failures": .array(failureSummary)]
    }

    // MARK: - Private
}
