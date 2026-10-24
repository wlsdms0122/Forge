//
//  WorkflowListActiveMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct WorkflowListActiveMethod: Sendable {
    // MARK: - Property
    let pool: WorkflowPool

    // MARK: - Initializer
    init(pool: WorkflowPool) {
        self.pool = pool
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        let snapshot = await pool.snapshot()
        let slots  = await pool.configuredSlots
        let free   = await pool.freeSlots
        let queued = await pool.queuedWaiters
        let rows: [JSONValue] = snapshot.map { info in
            var row: [String: JSONValue] = [
                "run_id":   .string(info.runID),
                "workflow_name": .string(info.workflowName),
                "origin":        info.origin.jsonValue,
                "principal":     .string(info.principal),
                "state":         .string(info.state.rawValue),
                "enqueued_at":   .int(Int(info.enqueuedAt.timeIntervalSince1970)),
                "held_slots":    .int(info.heldSlots)
            ]

            if let startedAt = info.startedAt {
                row["started_at"] = .int(Int(startedAt.timeIntervalSince1970))
            }

            return .object(row)
        }

        return [
            "workflows":                .array(rows),
            "maximum_concurrent_steps": .int(slots),
            "free_slots":               .int(free),
            "queued_waiters":           .int(queued)
        ]
    }

    // MARK: - Private
}
