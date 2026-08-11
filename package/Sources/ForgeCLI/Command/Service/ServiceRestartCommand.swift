//
//  ServiceRestartCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct ServiceRestartCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "restart",
        abstract: "Stop and start a managed service.",
        discussion: """
            The restarted process picks up the current `[service.<name>]`
            spec — pair with `forge service reload` to apply config changes.
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
        let client = Client(global, context: "service restart")
        
        printResult(client.call("service.restart", ["name": name]), json: json)
    }
    
    // MARK: - Private
}
