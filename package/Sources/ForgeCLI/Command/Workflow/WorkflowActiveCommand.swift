//
//  WorkflowActiveCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

struct WorkflowActiveCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "active",
        abstract: "Show runs the pool is currently tracking."
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
            result.printJSON()
            
            return
        }
        
        let rows = result["runs"]?.arrayValue ?? []
        
        if rows.isEmpty {
            print("(no active runs)")
        } else {
            for row in rows {
                let id = row["run_id"]?.stringValue ?? "?"
                let name = row["workflow_name"]?.stringValue ?? "?"
                let state = row["state"]?.stringValue ?? "?"
                let principal = row["principal"]?.stringValue ?? "?"
                
                print("\(id)\t\(name)\t\(state)\t\(principal)")
            }
        }
        
        let slots = result["maximum_concurrent_steps"]?.intValue ?? 0
        let free = result["free_slots"]?.intValue ?? 0
        let queued = result["queued_waiters"]?.intValue ?? 0
        
        print("slots: \(free) free / \(slots) total, \(queued) queued")
    }
    
    // MARK: - Private
}
