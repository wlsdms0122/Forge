//
//  ServiceDescribeCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

struct ServiceDescribeCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "describe",
        abstract: "Show a service handler's call schema.",
        discussion: """
            Prints the call contract of one registered service handler — its
            description and the actions/ops it accepts, with params and
            returns. This is the schema to consult before `forge service
            send <name>`.
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Service handler name.")
    var name: String
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "service describe")
        let result = client.call("handler.list")
        
        let services = result["services"]?.arrayValue ?? []
        
        guard let entry = services.first(
            where: { service in service["service"]?.stringValue == name }
        ) else {
            die("service describe: '\(name)' not registered", code: 5)
        }
        
        if json { entry.printJSON() } else { printServicePlain(entry) }
    }
    
    // MARK: - Private
    private func printServicePlain(_ service: JSONValue) {
        let name = service["service"]?.stringValue ?? "?"
        let schema = service["schema"]?.objectValue ?? [:]
        let description = schema["description"]?.stringValue ?? ""
        
        print(name)
        
        if !description.isEmpty { print("  \(description)") }
        
        if let actions = schema["actions"]?.arrayValue, !actions.isEmpty {
            print("")
            print("  actions:")
            
            for (index, action) in actions.enumerated() {
                if index > 0 { print("") }
                
                let kind = action["kind"]?.stringValue ?? "?"
                let actionDescription = action["description"]?.stringValue ?? ""
                
                if actionDescription.isEmpty {
                    print("    \(kind)")
                } else {
                    print("    \(kind) — \(actionDescription)")
                }
                
                if let params = action["params"]?.objectValue, !params.isEmpty {
                    print("      params:")
                    printParamRows(params, indent: "        ")
                }
                
                if let returns = action["returns"]?.objectValue, !returns.isEmpty {
                    print("      returns:")
                    printReturnRows(returns, indent: "        ")
                }
            }
        }
        
        if let ops = schema["ops"]?.arrayValue, !ops.isEmpty {
            print("")
            print("  ops:")
            
            for (index, op) in ops.enumerated() {
                if index > 0 { print("") }
                
                let opName = op["name"]?.stringValue ?? "?"
                let opDescription = op["description"]?.stringValue ?? ""
                
                if opDescription.isEmpty {
                    print("    \(opName)")
                } else {
                    print("    \(opName) — \(opDescription)")
                }
                
                if let params = op["params"]?.arrayValue {
                    let names = params.compactMap(\.stringValue)
                    
                    if names.count == params.count {
                        print("      params: \(names.joined(separator: ", "))")
                    }
                } else if let params = op["params"]?.objectValue, !params.isEmpty {
                    print("      params:")
                    printParamRows(params, indent: "        ")
                }
            }
        }
    }
    
    private func printParamRows(_ params: [String: JSONValue], indent: String) {
        let keys = params.keys.sorted()
        var rows: [(String, String, String, String)] = []
        
        for key in keys {
            guard let param = params[key]?.objectValue else {
                rows.append((key, "", "", ""))
                
                continue
            }
            
            let type = param["type"]?.stringValue ?? ""
            let required = param["required"]?.boolValue ?? false
            let description = param["description"]?.stringValue ?? ""
            
            rows.append((key, type, required ? "required" : "optional", description))
        }
        
        let keyWidth = rows.map { row in row.0.count }.max() ?? 0
        let typeWidth = rows.map { row in row.1.count }.max() ?? 0
        let requiredWidth = rows.map { row in row.2.count }.max() ?? 0
        
        for row in rows {
            let line = "\(indent)\(row.0.padding(toLength: keyWidth, withPad: " ", startingAt: 0))  "
                + "\(row.1.padding(toLength: typeWidth, withPad: " ", startingAt: 0))  "
                + "\(row.2.padding(toLength: requiredWidth, withPad: " ", startingAt: 0))"
            
            if row.3.isEmpty {
                print(line)
            } else {
                print("\(line)  \(row.3)")
            }
        }
    }
    
    private func printReturnRows(_ returns: [String: JSONValue], indent: String) {
        let keys = returns.keys.sorted()
        let keyWidth = keys.map { key in key.count }.max() ?? 0
        
        for key in keys {
            let type = returns[key].map { value in value.stringValue ?? value.plainText } ?? ""
            
            print("\(indent)\(key.padding(toLength: keyWidth, withPad: " ", startingAt: 0))  \(type)")
        }
    }
}
