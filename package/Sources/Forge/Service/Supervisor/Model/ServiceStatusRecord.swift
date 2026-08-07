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

    var dict: [String: Any] {
        var dictionary: [String: Any] = [
            "name":       name,
            "state":      state,
            "auto_spawn": autoSpawn,
            "crashes":    consecutiveCrashes,
        ]

        if let pid { dictionary["pid"] = Int(pid) }

        if let startedAt {
            dictionary["started_at"] = ISO8601DateFormatter().string(from: startedAt)
        }

        if let lastExitCode { dictionary["last_exit_code"] = Int(lastExitCode) }

        return dictionary
    }

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
