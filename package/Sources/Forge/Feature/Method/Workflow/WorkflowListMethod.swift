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
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        let snapshot = await store.catalog()
        let summary: [JSONValue] = snapshot.entries.map { entry in
            var listed: [String: JSONValue] = [
                "name":   .string(entry.workflow.name),
                "source": .string(entry.source)
            ]

            listed["description"] = entry.workflow.description.map(JSONValue.string)

            return .object(listed)
        }
        let failureSummary: [JSONValue] = snapshot.failures.map { failure in
            [
                "path":   .string(failure.path),
                "reason": .string(failure.reason),
                "mtime":  .string(ISO8601.string(failure.mtime))
            ]
        }

        return ["workflows": .array(summary), "failures": .array(failureSummary)]
    }

    // MARK: - Private
}
