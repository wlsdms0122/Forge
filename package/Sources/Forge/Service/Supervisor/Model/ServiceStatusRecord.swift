//
//  ServiceStatusRecord.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ServiceStatusRecord: Sendable {
    // MARK: - Property
    let name: String
    let state: String
    let pid: Int32?
    let startedAt: Date?
    let consecutiveCrashes: Int
    let lastExitCode: Int32?
    let autoSpawn: Bool

    var fields: [String: JSONValue] {
        var object: [String: JSONValue] = [
            "name":       .string(name),
            "state":      .string(state),
            "auto_spawn": .bool(autoSpawn),
            "crashes":    .int(consecutiveCrashes)
        ]

        if let pid { object["pid"] = .int(Int(pid)) }

        if let startedAt {
            object["started_at"] = .string(ISO8601DateFormatter().string(from: startedAt))
        }

        if let lastExitCode { object["last_exit_code"] = .int(Int(lastExitCode)) }

        return object
    }

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
