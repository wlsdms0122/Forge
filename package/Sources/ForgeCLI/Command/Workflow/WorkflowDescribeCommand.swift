//
//  WorkflowDescribeCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct WorkflowDescribeCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "describe",
        abstract: "Show a single workflow's calling contract — description, inputs, outputs.",
        discussion: """
            Returns the full schema needed to dispatch a workflow without grep'ing
            the YAML file: inputs (type/default/hint — a declared default, even
            `null`, marks the input optional) and outputs mapping.
            Counterpart to `service describe`. Plain output is human-readable;
            pass --json to parse.
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
        let result = client.call("workflow.describe", ["name": name])
        
        if json {
            printJSON(result)
            
            return
        }
        
        let resolvedName = result["name"] as? String ?? name
        let description = result["description"] as? String ?? ""
        let source = result["source"] as? String ?? ""
        
        print(resolvedName)
        
        if !description.isEmpty { print("  \(description)") }
        if !source.isEmpty { print("  source: \(source)") }
        
        let inputs = (result["inputs"] as? [String: Any]) ?? [:]
        
        if inputs.isEmpty {
            print("  inputs: (none)")
        } else {
            print("  inputs:")
            
            for key in inputs.keys.sorted() {
                let spec = inputs[key] as? [String: Any] ?? [:]
                var bits: [String] = []
                
                if let type = spec["type"] as? String { bits.append(type) }
                
                if spec.keys.contains("default") {
                    bits.append("optional")
                    
                    if let value = spec["default"], !(value is NSNull) {
                        bits.append("default=\(renderPlainValue(value))")
                    }
                }
                
                if let one = spec["oneOf"] as? [Any] {
                    bits.append("one_of=\(renderPlainValue(one))")
                }
                
                let header = bits.isEmpty
                    ? key
                    : "\(key) (\(bits.joined(separator: ", ")))"
                
                if let hint = spec["hint"] as? String, !hint.isEmpty {
                    print("    \(header) — \(hint)")
                } else {
                    print("    \(header)")
                }
            }
        }
        
        let outputs = (result["outputs"] as? [String: Any]) ?? [:]
        
        if !outputs.isEmpty {
            print("  outputs:")
            
            for key in outputs.keys.sorted() {
                let raw = outputs[key]
                let rendered: String
                
                if let string = raw as? String {
                    rendered = string
                } else if let any = raw,
                    let data = try? JSONSerialization.data(withJSONObject: any),
                    let string = String(data: data, encoding: .utf8) {
                    rendered = string
                } else {
                    rendered = ""
                }
                
                print("    \(key) ← \(rendered)")
            }
        }
    }
    
    // MARK: - Private
}

private func renderPlainValue(_ value: Any) -> String {
    if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
        return number.boolValue ? "true" : "false"
    }
    
    if value is NSNull { return "null" }
    if let string = value as? String { return string }
    
    if JSONSerialization.isValidJSONObject(value),
        let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ),
        let string = String(data: data, encoding: .utf8) {
        return string
    }
    
    return "\(value)"
}
