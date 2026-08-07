//
//  ServiceListCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct ServiceListCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List registered service handlers."
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
            method: "session.list",
            params: [:],
            token: token
        ) {
        case .err(let type, let message):
            dieRPC("service list", type: type, message: message)
        
        case .ok(let dict):
            let services = (dict["services"] as? [[String: Any]]) ?? []
            
            if json {
                printJSON(["services": services])
                
                return
            }
            
            if services.isEmpty {
                print("(no services registered)")
                
                return
            }
            
            for service in services {
                let name = service["service"] as? String ?? "?"
                let schema = service["schema"] as? [String: Any]
                let description = (schema?["description"] as? String) ?? ""
                
                print(description.isEmpty ? name : "\(name)\t\(description)")
            }
        }
    }
    
    // MARK: - Private
}
