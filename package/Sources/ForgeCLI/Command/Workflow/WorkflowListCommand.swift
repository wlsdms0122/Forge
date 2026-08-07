//
//  WorkflowListCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct WorkflowListCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List registered workflows."
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
            method: "workflow.list",
            params: [:],
            token: token
        ) {
        case .err(let type, let message):
            dieRPC("workflow list", type: type, message: message)
        
        case .ok(let dict):
            if json {
                printJSON(dict)
                
                return
            }
            
            let workflows = (dict["workflows"] as? [[String: Any]]) ?? []
            let failures  = (dict["failures"]  as? [[String: Any]]) ?? []
            
            if workflows.isEmpty && failures.isEmpty {
                print("(no workflows registered)")
                
                return
            }
            
            for workflow in workflows {
                let name = workflow["name"] as? String ?? "?"
                let description = workflow["description"] as? String ?? ""
                
                print(description.isEmpty ? name : "\(name)\t\(description)")
            }
            
            if !failures.isEmpty {
                print("")
                print("FAILED (\(failures.count)):")
                
                for failure in failures {
                    let path   = failure["path"]   as? String ?? "?"
                    let reason = failure["reason"] as? String ?? "?"
                    
                    print("  \(path): \(reason)")
                }
            }
        }
    }
    
    // MARK: - Private
}
