//
//  WorkflowListCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

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
        let client = Client(global, context: "workflow list")
        let result = client.call("workflow.list")
        
        if json {
            result.printJSON()
            
            return
        }
        
        let workflows = result["workflows"]?.arrayValue ?? []
        let failures  = result["failures"]?.arrayValue ?? []
        
        if workflows.isEmpty && failures.isEmpty {
            print("(no workflows registered)")
            
            return
        }
        
        for workflow in workflows {
            let name = workflow["name"]?.stringValue ?? "?"
            let description = workflow["description"]?.stringValue ?? ""
            
            print(description.isEmpty ? name : "\(name)\t\(description)")
        }
        
        if !failures.isEmpty {
            print("")
            print("FAILED (\(failures.count)):")
            
            for failure in failures {
                let path   = failure["path"]?.stringValue ?? "?"
                let reason = failure["reason"]?.stringValue ?? "?"
                
                print("  \(path): \(reason)")
            }
        }
    }
    
    // MARK: - Private
}
