//
//  ResourceReadCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

struct ResourceReadCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Read a single resource file."
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Path relative to resource_directory.")
    var path: String
    
    @Option(help: "Truncation cap in bytes — bytes beyond are dropped and truncated=true.")
    var maxBytes: Int?
    
    @Flag(help: "Emit JSON (path/body/size/truncated). Default prints body only.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "resource read")
        
        var params: [String: JSONValue] = ["path": .string(path)]
        
        if let maxBytes { params["maximum_bytes"] = .int(maxBytes) }
        
        let result = client.call("resource.read", params)
        
        if json {
            result.printJSON()
            
            return
        }
        
        print(result["body"]?.stringValue ?? "")
    }
    
    // MARK: - Private
}
