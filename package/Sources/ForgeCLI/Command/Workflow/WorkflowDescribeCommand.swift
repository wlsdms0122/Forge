//
//  WorkflowDescribeCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

struct WorkflowDescribeCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "describe",
        abstract: "Show a single workflow's calling contract — description, inputs, return type.",
        discussion: """
            Returns what dispatching a workflow needs without grep'ing the YAML
            file: its inputs, each with the type (Optional where a caller may
            leave it out) and the hint, and its return type. Counterpart to
            `service describe`. Plain output is human-readable; pass --json to
            parse.
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Registered workflow name.")
    var name: String
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "workflow describe")
        let result = client.call("workflow.describe", ["name": .string(name)])
        
        if json {
            result.printJSON()
            
            return
        }
        
        let resolvedName = result["name"]?.stringValue ?? name
        let description = result["description"]?.stringValue ?? ""
        let source = result["source"]?.stringValue ?? ""
        
        print(resolvedName)
        
        if !description.isEmpty { print("  \(description)") }
        if !source.isEmpty { print("  source: \(source)") }
        
        let inputs = result["inputs"]?.objectValue ?? [:]
        
        if inputs.isEmpty {
            print("  inputs: (none)")
        } else {
            print("  inputs:")
            
            for key in inputs.keys.sorted() {
                let spec = inputs[key]
                let type = spec?["type"]?.stringValue ?? ""
                let header = "\(key) (\(type))"
                
                if let hint = spec?["hint"]?.stringValue, !hint.isEmpty {
                    print("    \(header) — \(hint)")
                } else {
                    print("    \(header)")
                }
            }
        }
        
        if let returns = result["returns"]?.stringValue {
            print("  returns: \(returns)")
        }
    }
    
    // MARK: - Private
}
