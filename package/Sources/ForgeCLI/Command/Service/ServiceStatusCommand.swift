//
//  ServiceStatusCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

struct ServiceStatusCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show supervisor state of all managed services.",
        discussion: """
            One line per `[service.<name>]` entry: process state
            (running / backoff / failed / stopped), pid, crash count, and
            `registered`: whether the service is currently
            registered on the daemon (the actual readiness signal).
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "service status")
        let result = client.call("service.status")
        
        if json {
            result.printJSON()
            
            return
        }
        
        let services = result["services"]?.arrayValue ?? []
        
        if services.isEmpty {
            print("(no services configured)")
            
            return
        }
        
        for service in services {
            let name = service["name"]?.stringValue ?? "?"
            let state = service["state"]?.stringValue ?? "?"
            let registered = (service["registered"]?.boolValue ?? false) ? "registered" : "-"
            let pid = service["pid"]?.intValue.map { pid in "pid=\(pid)" } ?? ""
            let crashes = service["crashes"]?.intValue
                .flatMap { count in count > 0 ? "crashes=\(count)" : nil } ?? ""
            let parts = [name, state, registered, pid, crashes]
                .filter { part in !part.isEmpty }
            
            print(parts.joined(separator: "\t"))
        }
    }
    
    // MARK: - Private
}
