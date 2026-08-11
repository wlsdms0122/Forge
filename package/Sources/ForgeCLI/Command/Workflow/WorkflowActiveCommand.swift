//
//  WorkflowActiveCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct WorkflowActiveCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "active",
        abstract: "Show workflows the pool is currently tracking."
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "workflow active")
        let result = client.call("workflow.list_active")
        
        if json {
            printJSON(result)
            
            return
        }
        
        let rows = (result["workflows"] as? [[String: Any]]) ?? []
        
        if rows.isEmpty {
            print("(no active workflows)")
        } else {
            for row in rows {
                let id = row["workflow_id"] as? String ?? "?"
                let name = row["workflow_name"] as? String ?? "?"
                let state = row["state"] as? String ?? "?"
                let principal = row["principal"] as? String ?? "?"
                
                print("\(id)\t\(name)\t\(state)\t\(principal)")
            }
        }
        
        let slots = result["maximum_concurrent_steps"] as? Int ?? 0
        let free = result["free_slots"] as? Int ?? 0
        let queued = result["queued_waiters"] as? Int ?? 0
        
        print("slots: \(free) free / \(slots) total, \(queued) queued")
    }
    
    // MARK: - Private
}
