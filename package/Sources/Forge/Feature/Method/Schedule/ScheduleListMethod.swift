//
//  ScheduleListMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ScheduleListMethod: Sendable {
    // MARK: - Property
    let store: ScheduleStore
    let ledger: FireLedger

    // MARK: - Initializer
    init(store: ScheduleStore, ledger: FireLedger) {
        self.store = store
        self.ledger = ledger
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        let now = Date()
        let ledgerMap = await ledger.snapshot()
        let catalog = await store.catalog()

        var flags: [JSONValue] = []

        let summary: [JSONValue] = try catalog.entries.map { entry in
            let schedule = entry.schedule
            let record = ledgerMap[schedule.id]
            let next = schedule.trigger.nextFire(after: record?.attemptedSlot, now: now)
            var row: [String: JSONValue] = [
                "id":          .string(schedule.id),
                "workflow":    .string(schedule.workflow),
                "trigger":     try JSONValue(encoding: schedule.trigger),
                "concurrency": .string(schedule.concurrency.rawValue),
                "enabled":     .bool(schedule.enabled),
                "runtime":     .bool(entry.runtime),
                "inputs":      .object(schedule.inputs ?? [:]),
                "source":      .string(entry.source)
            ]

            if let record {
                row["last_attempt_at"] = .string(ISO8601.string(record.recordedAt))

                switch record.state {
                case .pending:
                    break

                case .unknown:
                    row["last_outcome"] = "unknown"

                case .closed(let disposition):
                    row["last_outcome"] = .string(disposition.label)

                    if let reason = disposition.reason { row["reason"] = .string(reason) }
                    if let at = record.closedAt { row["outcome_at"] = .string(ISO8601.string(at)) }

                    if case .denied(let reason) = disposition {
                        var flag: [String: JSONValue] = [
                            "kind": "schedule_denied",
                            "schedule_id": .string(schedule.id),
                            "reason": .string(reason)
                        ]

                        if let at = record.closedAt { flag["outcome_at"] = .string(ISO8601.string(at)) }

                        flags.append(.object(flag))
                    }
                }
            }

            if let next { row["next_fire_at"] = .string(ISO8601.string(next)) }
            if schedule.trigger.isOneShot { row["spent"] = .bool(next == nil && record != nil) }

            return .object(row)
        }
        let failureSummary: [JSONValue] = catalog.failures.map { failure in
            [
                "path": .string(failure.path),
                "reason": .string(failure.reason),
                "mtime": .string(ISO8601.string(failure.mtime))
            ]
        }

        return ["schedules": .array(summary), "failures": .array(failureSummary), "flags": .array(flags)]
    }

    // MARK: - Private
}
