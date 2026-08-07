//
//  WorkflowListActiveMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

struct WorkflowListActiveMethod: Sendable {
    // MARK: - Property
    let pool: WorkflowPool
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(pool: WorkflowPool, tokenAuthority: TokenAuthority) {
        self.pool = pool
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        _ = try tokenAuthority.requireClaims(request.params)

        let snapshot = await pool.snapshot()
        let slots  = await pool.configuredSlots
        let free   = await pool.freeSlots
        let queued = await pool.queuedWaiters
        let rows: [[String: Any]] = snapshot.map { info in
            var row: [String: Any] = [
                "workflow_id":   info.workflowID,
                "workflow_name": info.workflowName,
                "origin":       info.origin.asPayload,
                "principal":     info.principal,
                "state":         info.state.rawValue,
                "enqueued_at":   Int(info.enqueuedAt.timeIntervalSince1970),
                "held_slots":    info.heldSlots,
            ]

            if let startedAt = info.startedAt {
                row["started_at"] = Int(startedAt.timeIntervalSince1970)
            }

            return row
        }

        return [
            "workflows":            rows,
            "maximum_concurrent_steps": slots,
            "free_slots":           free,
            "queued_waiters":       queued,
        ]
    }

    // MARK: - Private
}
