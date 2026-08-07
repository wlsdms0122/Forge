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
        let socketPath = try resolveSocket(global)
        let token = resolveToken(global.token)
        
        switch callRPC(
            socketPath: socketPath,
            method: "resource.list",
            params: [:],
            token: token
        ) {
        case .err(let type, let message):
            dieRPC("resource list", type: type, message: message)
        
        case .ok(let dictionary):
            if json {
                printJSON(dictionary)
                
                return
            }
            
            let rows = (dictionary["resources"] as? [[String: Any]]) ?? []
            
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
    }
    
    // MARK: - Private
}
