//
//  PolicyListMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

struct PolicyListMethod: Sendable {
    // MARK: - Property
    let store: PolicyStore
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(store: PolicyStore, tokenAuthority: TokenAuthority) {
        self.store = store
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        _ = try tokenAuthority.requireClaims(request.params)

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
