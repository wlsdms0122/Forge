//
//  JobListMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct JobListMethod: Sendable {
    // MARK: - Property
    let store: JobStore

    // MARK: - Initializer
    init(store: JobStore) {
        self.store = store
    }

    // MARK: - Public
    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONValue {
        var jobs = await store.all()

        if let status = request.params["status"]?.stringValue, !status.isEmpty {
            jobs = jobs.filter { job in job.status == status }
        }

        if let key = request.params["origin_key"]?.stringValue, !key.isEmpty,
            let value = request.params["origin_value"]?.stringValue {
            jobs = jobs.filter { job in
                guard let origin = job.origin?[key], case .string(let string) = origin else {
                    return false
                }

                return string == value
            }
        }

        let summary: [JSONValue] = jobs
            .sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }
            .map { job in
                var row: [String: JSONValue] = [
                    "id":         .string(job.id),
                    "title":      .string(job.title),
                    "status":     .string(job.status),
                    "updated_at": .string(job.updatedAt),
                    "open":       .bool(job.isOpen(excluding: claims.id))
                ]

                if let last = job.events.last {
                    row["last_event"] = ["ts": .string(last.ts), "kind": .string(last.kind.rawValue)]
                }

                if let parent = job.parentJob { row["parent_job"] = .string(parent) }
                if !job.children.isEmpty { row["children"] = .array(job.children.map(JSONValue.string)) }
                if let origin = job.origin { row["origin"] = .object(origin) }

                return .object(row)
            }

        return ["jobs": .array(summary)]
    }

    // MARK: - Private
}
