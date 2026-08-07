//
//  ServiceConfig.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ServiceConfig: Sendable, Equatable {
    struct RestartPolicy: Sendable, Equatable {
        // MARK: - Property
        let backoffInitial: Duration
        let backoffMax: Duration
        let crashLoopLimit: Int
        let stableUptime: Duration

        // MARK: - Initializer
        init(
            backoffInitial: Duration = .seconds(1),
            backoffMax: Duration = .seconds(30),
            crashLoopLimit: Int = 5,
            stableUptime: Duration = .seconds(60)
        ) {
            self.backoffInitial = backoffInitial
            self.backoffMax = backoffMax
            self.crashLoopLimit = crashLoopLimit
            self.stableUptime = stableUptime
        }

        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let name: String
    let command: [String]
    let workingDirectory: URL?
    let environment: [String: String]
    let autoSpawn: Bool
    let logFile: URL?
    let restart: RestartPolicy

    // MARK: - Initializer
    init(
        name: String,
        command: [String],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:],
        autoSpawn: Bool = true,
        logFile: URL? = nil,
        restart: RestartPolicy = RestartPolicy()
    ) {
        self.name = name
        self.command = command
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.autoSpawn = autoSpawn
        self.logFile = logFile
        self.restart = restart
    }

    // MARK: - Public
    // MARK: - Private
}
