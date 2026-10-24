//
//  WorkflowListMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct WorkflowListMethod: Sendable {
    // MARK: - Property
    let store: WorkflowCatalog

    // MARK: - Initializer
    init(store: WorkflowCatalog) {
        self.store = store
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        let catalog = await store.catalog()
        let summary: [[String: Any]] = catalog.entries.map { entry in
            var listed: [String: Any] = [
                "name":        entry.workflow.name,
                "source":      entry.source,
            ]

            if let description = entry.workflow.description {
                listed["description"] = description
            }

            return listed
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
