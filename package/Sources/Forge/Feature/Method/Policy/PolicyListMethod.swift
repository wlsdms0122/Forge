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
        let snapshot = await store.reload()
        let policy = snapshot.policy.mapValues { workflows in JSONValue.array(workflows.map(JSONValue.string)) }
        let failureSummary: [JSONValue] = snapshot.failures.map { failure in
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
