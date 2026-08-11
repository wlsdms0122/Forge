//
//  ServiceCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
//

import ArgumentParser
import Foundation

struct ServiceCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "service",
        abstract: "Manage, inspect, and call managed services.",
        discussion: """
            A service (e.g. `slack`) is a process that implements a capability
            forge itself does not. forge is the supervisor: services are
            declared in `.forge/config.toml` `[service.<name>]`, spawned by the
            daemon (auto_spawn or `run`), monitored, and restarted with
            backoff when they crash.

            CONTROL    run / shutdown / restart / status / reload
            INSPECT    list / describe  (registered handler schemas)
            CALL       send             (hand a payload to a service)
            INTERNAL   register         (the bridge a spawned service runs)
            """,
        subcommands: [
            ServiceRunCommand.self,
            ServiceShutdownCommand.self,
            ServiceRestartCommand.self,
            ServiceStatusCommand.self,
            ServiceReloadCommand.self,
            ServiceListCommand.self,
            ServiceDescribeCommand.self,
            ServiceRegisterCommand.self,
            ServiceSendCommand.self,
        ]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
