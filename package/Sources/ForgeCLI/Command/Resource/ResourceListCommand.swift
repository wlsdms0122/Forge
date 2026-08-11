//
//  ResourceListCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct ResourceListCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List files in resource_directory."
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "resource list")
        let result = client.call("resource.list")
        
        if json {
            printJSON(result)
            
            return
        }
        
        let rows = (result["resources"] as? [[String: Any]]) ?? []
        
        if rows.isEmpty {
            print("(no resources)")
            
            return
        }
        
        for row in rows {
            let path = row["path"] as? String ?? "?"
            let size = row["size"] as? Int ?? 0
            let mtime = row["mtime"] as? String ?? "?"
            
            print("\(path)\t\(size)\t\(mtime)")
        }
    }
    
    // MARK: - Private
}
