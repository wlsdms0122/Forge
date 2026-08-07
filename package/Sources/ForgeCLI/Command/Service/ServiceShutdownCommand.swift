//
//  ServiceShutdownCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct ServiceShutdownCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "shutdown",
        abstract: "Stop a managed service (SIGTERM, then SIGKILL after 5s).",
        discussion: """
            The stop is volatile: on the next daemon boot, `auto_spawn` in
            the toml is the truth again and the service comes back up.
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Service name.")
    var name: String
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        controlCall(
            global: global,
            method: "service.shutdown",
            params: ["name": name],
            context: "service shutdown",
            json: json
        )
    }
    
    // MARK: - Private
}
