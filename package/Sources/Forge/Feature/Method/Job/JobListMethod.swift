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
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(store: JobStore, tokenAuthority: TokenAuthority) {
        self.store = store
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        let claims = try tokenAuthority.requireClaims(request.params)
        var jobs = await store.all()

        if let status = request.params["status"] as? String, !status.isEmpty {
            jobs = jobs.filter { job in job.status == status }
        }

        if let key = request.params["origin_key"] as? String, !key.isEmpty,
            let value = request.params["origin_value"] as? String {
            jobs = jobs.filter { job in
                guard let origin = job.origin?[key], case .string(let string) = origin else {
                    return false
                }

                return string == value
            }
        }

        let summary: [[String: Any]] = jobs
            .sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }
            .map { job in
                var row: [String: Any] = [
                    "id":         job.id,
                    "title":      job.title,
                    "status":     job.status,
                    "updated_at": job.updatedAt,
                    "open":       job.isOpen(excluding: claims.id),
                ]

                if let last = job.events.last {
                    row["last_event"] = ["ts": last.ts, "kind": last.kind.rawValue]
                }

                if let parent = job.parentJob { row["parent_job"] = parent }
                if !job.children.isEmpty { row["children"] = job.children }
                if let origin = job.origin { row["origin"] = jsonValueDictToAny(origin) }

                return row
            }

        return ["jobs": summary]
    }

    // MARK: - Private
}
