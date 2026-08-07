//
//  ResourceReadCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

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
        let socketPath = try resolveSocket(global)
        let token = resolveToken(global.token)
        
        var params: [String: Any] = ["path": path]
        
        if let maxBytes { params["maximum_bytes"] = maxBytes }
        
        switch callRPC(
            socketPath: socketPath,
            method: "resource.read",
            params: params,
            token: token
        ) {
        case .err(let type, let message):
            dieRPC("resource read", type: type, message: message)
        
        case .ok(let dictionary):
            if json {
                printJSON(dictionary)
                
                return
            }
            
            print((dictionary["body"] as? String) ?? "")
        }
    }
    
    // MARK: - Private
}
