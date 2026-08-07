//
//  ServiceDescribeCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct ServiceDescribeCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "describe",
        abstract: "Show a service handler's call schema.",
        discussion: """
            Prints the call contract of one registered service handler — its
            description and the actions/ops it accepts, with params and
            returns. This is the schema to consult before `forge service
            send <name>`.
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Service handler name.")
    var name: String
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let socketPath = try resolveSocket(global)
        let token = resolveToken(global.token)
        
        switch callRPC(
            socketPath: socketPath,
            method: "session.list",
            params: [:],
            token: token
        ) {
        case .err(let type, let message):
            dieRPC("service describe", type: type, message: message)
        
        case .ok(let dict):
            let services = (dict["services"] as? [[String: Any]]) ?? []
            
            guard let entry = services.first(
                where: { service in (service["service"] as? String) == name }
            ) else {
                die("service describe: '\(name)' not registered", code: 5)
            }
            
            if json { printJSON(entry) } else { printServicePlain(entry) }
        }
    }
    
    // MARK: - Private
}
