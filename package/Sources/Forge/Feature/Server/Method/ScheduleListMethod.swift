//
//  ScheduleListMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

struct ScheduleListMethod: Sendable {
    // MARK: - Property
    let store: ScheduleStore
    let ledger: FireLedger
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(store: ScheduleStore, ledger: FireLedger, tokenAuthority: TokenAuthority) {
        self.store = store
        self.ledger = ledger
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        _ = try tokenAuthority.requireClaims(request.params)

        let now = Date()
        let ledgerMap = await ledger.snapshot()
        let catalog = await store.catalog()

        var flags: [[String: Any]] = []

        let summary: [[String: Any]] = catalog.entries.map { entry in
            let schedule = entry.schedule
            let record = ledgerMap[schedule.id]
            let next = schedule.trigger.nextFire(after: record?.attemptedSlot, now: now)
            var row: [String: Any] = [
                "id":          schedule.id,
                "workflow":    schedule.workflow,
                "trigger":  triggerToAny(schedule.trigger),
                "concurrency": schedule.concurrency.rawValue,
                "enabled":     schedule.enabled,
                "runtime":   entry.runtime,
                "inputs":      jsonValueDictToAny(schedule.inputs ?? [:]),
                "source":      entry.source,
            ]

            if let record {
                row["last_attempt_at"] = ISO8601.string(record.recordedAt)

                switch record.state {
                case .pending:
                    break

                case .unknown:
                    row["last_outcome"] = "unknown"

                case .closed(let disposition):
                    row["last_outcome"] = disposition.label

                    if let reason = disposition.reason { row["reason"] = reason }
                    if let at = record.closedAt { row["outcome_at"] = ISO8601.string(at) }

                    if case .denied(let reason) = disposition {
                        var flag: [String: Any] = [
                            "kind": "schedule_denied",
                            "schedule_id": schedule.id,
                            "reason": reason,
                        ]

                        if let at = record.closedAt { flag["outcome_at"] = ISO8601.string(at) }

                        flags.append(flag)
                    }
                }
            }

            if let next { row["next_fire_at"] = ISO8601.string(next) }
            if schedule.trigger.isOneShot { row["spent"] = (next == nil && record != nil) }

            return row
        }
        let failureSummary: [[String: Any]] = catalog.failures.map { failure in
            [
                "path": failure.path,
                "reason": failure.reason,
                "mtime": ISO8601.string(failure.mtime),
            ]
        }

        return ["schedules": summary, "failures": failureSummary, "flags": flags]
    }

    // MARK: - Private
}

func triggerToAny(_ trigger: Trigger) -> [String: Any] {
    switch trigger {
    case .every(let interval):
        return ["every": Interval.format(interval.seconds)]

    case .once(let fireAt, let timezone):
        return [
            "once": Trigger.formatWallClock(fireAt, timezone: timezone),
            "timezone": timezone.identifier,
        ]

    case .at(let hour, let minute, let days, let timezone):
        var out: [String: Any] = [
            "at": String(format: "%02d:%02d", hour, minute),
            "timezone": timezone.identifier,
        ]

        if !days.isEmpty {
            out["days"] = Weekday.allCases
                .filter { weekday in days.contains(weekday) }
                .map(\.rawValue)
        }

        return out
    }
}
