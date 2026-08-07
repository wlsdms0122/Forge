//
//  WorkflowHealthMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

struct WorkflowHealthMethod: Sendable {
    enum Advisory {
        // MARK: - Property
        static let longWaitMs   = 60_000
        static let longRunMs    = 1_800_000
        static let bigTreeRuns  = 16
        static let highRate60s  = 30
        static let refused60s   = 1

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let pool: WorkflowPool
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(pool: WorkflowPool, tokenAuthority: TokenAuthority) {
        self.pool = pool
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    static func computeFlags(_ health: WorkflowPool.HealthSnapshot) -> [[String: Any]] {
        var flags: [[String: Any]] = []

        for waiter in health.waiters where waiter.waitedMs >= Advisory.longWaitMs {
            flags.append([
                "kind": "long_wait",
                "class": "saturation",
                "workflow_id": waiter.workflowID,
                "waited_ms": waiter.waitedMs,
            ])
        }

        for run in health.oldestRuns where run.ageMs >= Advisory.longRunMs {
            flags.append([
                "kind": "long_run",
                "class": "anomaly",
                "workflow_id": run.workflowID,
                "workflow_name": run.workflowName,
                "age_ms": run.ageMs,
            ])
        }

        for tree in health.trees where tree.count >= Advisory.bigTreeRuns {
            flags.append([
                "kind": "big_tree",
                "class": "anomaly",
                "root_id": tree.rootID,
                "runs": tree.count,
            ])
        }

        if health.dispatchesLast60s >= Advisory.highRate60s {
            flags.append([
                "kind": "high_rate",
                "class": "anomaly",
                "dispatches_last_60s": health.dispatchesLast60s,
            ])
        }

        if health.refusedLast60s >= Advisory.refused60s {
            flags.append([
                "kind": "runs_refused",
                "class": "saturation",
                "refused_last_60s": health.refusedLast60s,
                "total": health.refusedRuns,
            ])
        }

        return flags
    }

    func handle(_ request: RPCRequest) async throws -> JSONObject {
        _ = try tokenAuthority.requireClaims(request.params)

        let health = await pool.health()

        return [
            "slots": [
                "max":  health.slotsMax,
                "free": health.slotsFree,
                "waiters": health.waiters.map { waiter in
                    ["workflow_id": waiter.workflowID, "waited_ms": waiter.waitedMs]
                },
            ] as [String: Any],
            "runs": [
                "active":        health.activeRuns,
                "cap":           health.runCap,
                "refused_total": health.refusedRuns,
                "oldest": health.oldestRuns.map { run in
                    [
                        "workflow_id": run.workflowID,
                        "workflow_name": run.workflowName,
                        "state": run.state,
                        "age_ms": run.ageMs,
                    ]
                },
                "trees": health.trees.map { tree in
                    ["root_id": tree.rootID, "runs": tree.count, "names": tree.names]
                },
            ] as [String: Any],
            "dispatch": ["last_60s": health.dispatchesLast60s] as [String: Any],
            "flags": Self.computeFlags(health),
        ]
    }

    // MARK: - Private
}
