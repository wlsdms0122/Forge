//
//  ServiceListCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

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
        let result = client.call("handler.list")
        
        let services = result["services"]?.arrayValue ?? []
        
        if json {
            JSONValue.object(["services": .array(services)]).printJSON()
            
            return
        }
        
        if services.isEmpty {
            print("(no services registered)")
            
            return
        }
        
        for service in services {
            let name = service["service"]?.stringValue ?? "?"
            let description = service["schema"]?["description"]?.stringValue ?? ""
            
            print(description.isEmpty ? name : "\(name)\t\(description)")
        }
    }
    
    // MARK: - Private
}
