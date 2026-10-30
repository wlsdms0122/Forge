//
//  WorkflowListMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct WorkflowListMethod: Sendable {
    // MARK: - Property
    let catalog: WorkflowCatalog

    // MARK: - Initializer
    init(catalog: WorkflowCatalog) {
        self.catalog = catalog
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        let snapshot = await catalog.reload()
        let summary: [JSONValue] = snapshot.entries.map { workflow in
            var listed: [String: JSONValue] = ["path": .string(workflow.path)]

            listed["description"] = workflow.description.map(JSONValue.string)

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
