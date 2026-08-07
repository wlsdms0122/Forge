//
//  PolicyListCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct PolicyListCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Dump the merged policy in daemon memory."
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Flag(help: "Emit JSON instead of plain text.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let socketPath = try resolveSocket(global)
        let token = resolveToken(global.token)
        
        switch callRPC(socketPath: socketPath, method: "policy.list", params: [:], token: token) {
        case .ok(let dictionary):
            if json {
                printJSON(dictionary)
                
                return
            }
            
            let policy = (dictionary["policy"] as? [String: [String]]) ?? [:]
            
            if policy.isEmpty {
                print("(empty)")
                
                return
            }
            
            let width = policy.keys.map { key in key.count }.max() ?? 0
            
            for key in policy.keys.sorted() {
                let padding = String(repeating: " ", count: width - key.count)
                let workflows = (policy[key] ?? []).joined(separator: ", ")
                
                print("\(key)\(padding)  →  \(workflows)")
            }
        
        case .err(let type, let message):
            dieRPC("policy list", type: type, message: message)
        }
    }
    
    // MARK: - Private
}
