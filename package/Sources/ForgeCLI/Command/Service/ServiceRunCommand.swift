//
//  ServiceRunCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct ServiceRunCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Start a managed service (declared in .forge/config.toml).",
        discussion: """
            Spawns the service process under the daemon's supervisor.
            Idempotent — running services are left alone. A service that hit
            its crash loop limit (state `failed`) is given a fresh start.
            Only services declared in `[service.<name>]` can be run; for a
            new entry, edit the toml and `forge service reload` first.
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Service name (a `[service.<name>]` entry).")
    var name: String
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "service run")
        
        printResult(client.call("service.run", ["name": name]), json: json)
    }
    
    // MARK: - Private
}
