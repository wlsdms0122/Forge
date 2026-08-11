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
        let client = Client(global, context: "service list")
        let result = client.call("session.list")
        
        let services = (result["services"] as? [[String: Any]]) ?? []
        
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
    
    // MARK: - Private
}
