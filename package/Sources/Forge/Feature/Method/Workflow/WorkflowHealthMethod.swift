//
//  WorkflowHealthMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

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

    // MARK: - Initializer
    init(pool: WorkflowPool) {
        self.pool = pool
    }

    // MARK: - Public
    static func computeFlags(_ health: WorkflowPool.HealthSnapshot) -> [JSONValue] {
        var flags: [JSONValue] = []

        for waiter in health.waiters where waiter.waitedMs >= Advisory.longWaitMs {
            flags.append([
                "kind": "long_wait",
                "class": "saturation",
                "workflow_id": .string(waiter.workflowID),
                "waited_ms": .int(waiter.waitedMs)
            ])
        }

        for run in health.oldestRuns where run.ageMs >= Advisory.longRunMs {
            flags.append([
                "kind": "long_run",
                "class": "anomaly",
                "workflow_id": .string(run.workflowID),
                "workflow_name": .string(run.workflowName),
                "age_ms": .int(run.ageMs)
            ])
        }

        for tree in health.trees where tree.count >= Advisory.bigTreeRuns {
            flags.append([
                "kind": "big_tree",
                "class": "anomaly",
                "root_id": .string(tree.rootID),
                "runs": .int(tree.count)
            ])
        }

        if health.dispatchesLast60s >= Advisory.highRate60s {
            flags.append([
                "kind": "high_rate",
                "class": "anomaly",
                "dispatches_last_60s": .int(health.dispatchesLast60s)
            ])
        }

        if health.refusedLast60s >= Advisory.refused60s {
            flags.append([
                "kind": "runs_refused",
                "class": "saturation",
                "refused_last_60s": .int(health.refusedLast60s),
                "total": .int(health.refusedRuns)
            ])
        }

        return flags
    }

    func handle(_ request: RPCRequest) async throws -> JSONValue {
        let health = await pool.health()
        let waiters: [JSONValue] = health.waiters.map { waiter in
            ["workflow_id": .string(waiter.workflowID), "waited_ms": .int(waiter.waitedMs)]
        }
        let oldest: [JSONValue] = health.oldestRuns.map { run in
            [
                "workflow_id": .string(run.workflowID),
                "workflow_name": .string(run.workflowName),
                "state": .string(run.state),
                "age_ms": .int(run.ageMs)
            ]
        }
        let trees: [JSONValue] = health.trees.map { tree in
            [
                "root_id": .string(tree.rootID),
                "runs": .int(tree.count),
                "names": .object(tree.names.mapValues(JSONValue.int))
            ]
        }

        return [
            "slots": [
                "max":     .int(health.slotsMax),
                "free":    .int(health.slotsFree),
                "waiters": .array(waiters)
            ],
            "runs": [
                "active":        .int(health.activeRuns),
                "cap":           .int(health.runCap),
                "refused_total": .int(health.refusedRuns),
                "oldest":        .array(oldest),
                "trees":         .array(trees)
            ],
            "dispatch": ["last_60s": .int(health.dispatchesLast60s)],
            "flags": .array(Self.computeFlags(health))
        ]
    }

    // MARK: - Private
}
