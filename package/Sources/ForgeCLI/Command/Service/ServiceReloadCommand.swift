//
//  ServiceReloadCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct ServiceReloadCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "reload",
        abstract: "Re-read [service] entries from .forge/config.toml.",
        discussion: """
            Applies the current toml to the supervisor: removed services are
            stopped, added ones with auto_spawn start immediately, changed
            specs take effect on the next (re)start.
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "service reload")
        
        printResult(client.call("service.reload"), json: json)
    }
    
    // MARK: - Private
}
