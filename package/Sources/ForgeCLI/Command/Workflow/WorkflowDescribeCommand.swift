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
            file: its inputs (the type, where an Optional type is one a caller
            may leave out; the default the file writes; the hint) and its return
            type. Counterpart to `service describe`. Plain output is
            human-readable; pass --json to parse.
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
            printJSON(result)
            
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
                var bits: [String] = []
                
                if let type = spec?["type"]?.stringValue { bits.append(type) }
                
                if let value = spec?["default"] { bits.append("default=\(value.stringValue ?? value.plainText)") }
                
                let header = bits.isEmpty
                    ? key
                    : "\(key) (\(bits.joined(separator: ", ")))"
                
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
