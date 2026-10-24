//
//  JobShowMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct JobShowMethod: Sendable {
    // MARK: - Property
    let store: JobStore
    let workRegistry: WorkRegistry

    // MARK: - Initializer
    init(store: JobStore, workRegistry: WorkRegistry) {
        self.store = store
        self.workRegistry = workRegistry
    }

    // MARK: - Public
    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONValue {
        guard let id = request.params["id"]?.stringValue, !id.isEmpty else {
            throw ProtocolError("job.show: 'id' (string) required")
        }


        guard let job = await store.lookup(id) else {
            throw ProtocolError("job not found: \(id)")
        }

        await store.recordTouch(
            id: id,
            claims: claims,
            workRegistry: workRegistry,
            via: "job.show"
        )

        var dictionary = try JSONValue(encoding: job).objectValue ?? [:]
        dictionary["open"] = .bool(job.isOpen(excluding: claims.id))

        if !job.children.isEmpty {
            var detail: [JSONValue] = []

            for childID in job.children {
                if let child = await store.lookup(childID) {
                    detail.append([
                        "id": .string(child.id),
                        "title": .string(child.title),
                        "status": .string(child.status)
                    ])
                } else {
                    detail.append(["id": .string(childID), "status": "missing"])
                }
            }

            dictionary["children_detail"] = .array(detail)
        }

        return ["job": .object(dictionary)]
    }

    // MARK: - Private
}
