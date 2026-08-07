//
//  ServiceStatusCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct ServiceStatusCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show supervisor state of all managed services.",
        discussion: """
            One line per `[service.<name>]` entry: process state
            (running / backoff / failed / stopped), pid, crash count, and
            `registered` — whether the service's handler is currently
            registered on the daemon (the actual readiness signal).
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let socketPath = try resolveSocket(global)
        let token = resolveToken(global.token)
        
        switch callRPC(
            socketPath: socketPath,
            method: "service.status",
            params: [:],
            token: token
        ) {
        case .err(let type, let message):
            dieRPC("service status", type: type, message: message)
        
        case .ok(let dict):
            if json {
                printJSON(dict)
                
                return
            }
            
            let services = (dict["services"] as? [[String: Any]]) ?? []
            
            if services.isEmpty {
                print("(no services configured)")
                
                return
            }
            
            for service in services {
                let name = service["name"] as? String ?? "?"
                let state = service["state"] as? String ?? "?"
                let registered = (service["registered"] as? Bool ?? false) ? "registered" : "-"
                let pid = (service["pid"] as? Int).map { pid in "pid=\(pid)" } ?? ""
                let crashes = (service["crashes"] as? Int)
                    .flatMap { count in count > 0 ? "crashes=\(count)" : nil } ?? ""
                let parts = [name, state, registered, pid, crashes]
                    .filter { part in !part.isEmpty }
                
                print(parts.joined(separator: "\t"))
            }
        }
    }
    
    // MARK: - Private
}
