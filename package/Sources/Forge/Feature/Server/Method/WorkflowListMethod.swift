//
//  WorkflowListMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

struct WorkflowListMethod: Sendable {
    // MARK: - Property
    let store: SpecCatalog
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(store: SpecCatalog, tokenAuthority: TokenAuthority) {
        self.store = store
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        _ = try tokenAuthority.requireClaims(request.params)

        let catalog = await store.catalog()
        let summary: [[String: Any]] = catalog.entries.map { entry in
            [
                "name":        entry.name,
                "description": entry.program.description as Any? ?? NSNull(),
                "source":      entry.source,
            ]
        }
        let failureSummary: [[String: Any]] = catalog.failures.map { failure in
            [
                "path":   failure.path,
                "reason": failure.reason,
                "mtime":  ISO8601.string(failure.mtime),
            ]
        }

        return ["workflows": summary, "failures": failureSummary]
    }

    // MARK: - Private
}
