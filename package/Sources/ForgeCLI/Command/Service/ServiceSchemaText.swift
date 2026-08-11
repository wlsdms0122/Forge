//
//  ServiceSchemaText.swift
//  ForgeCLI
//
//  Created by JSilver on 8/11/26.
//

import Foundation

func printServicePlain(_ service: [String: Any]) {
    let name = service["service"] as? String ?? "?"
    let schema = service["schema"] as? [String: Any] ?? [:]
    let description = (schema["description"] as? String) ?? ""
    
    print(name)
    
    if !description.isEmpty { print("  \(description)") }
    
    if let actions = schema["actions"] as? [[String: Any]], !actions.isEmpty {
        print("")
        print("  actions:")
        
        for (index, action) in actions.enumerated() {
            if index > 0 { print("") }
            
            let kind = action["kind"] as? String ?? "?"
            let actionDescription = action["description"] as? String ?? ""
            
            if actionDescription.isEmpty {
                print("    \(kind)")
            } else {
                print("    \(kind) — \(actionDescription)")
            }
            
            if let params = action["params"] as? [String: Any], !params.isEmpty {
                print("      params:")
                printParamRows(params, indent: "        ")
            }
            
            if let returns = action["returns"] as? [String: Any], !returns.isEmpty {
                print("      returns:")
                printReturnRows(returns, indent: "        ")
            }
        }
    }
    
    if let ops = schema["ops"] as? [[String: Any]], !ops.isEmpty {
        print("")
        print("  ops:")
        
        for (index, op) in ops.enumerated() {
            if index > 0 { print("") }
            
            let opName = op["name"] as? String ?? "?"
            let opDescription = op["description"] as? String ?? ""
            
            if opDescription.isEmpty {
                print("    \(opName)")
            } else {
                print("    \(opName) — \(opDescription)")
            }
            
            if let params = op["params"] as? [String] {
                print("      params: \(params.joined(separator: ", "))")
            } else if let params = op["params"] as? [String: Any], !params.isEmpty {
                print("      params:")
                printParamRows(params, indent: "        ")
            }
        }
    }
}

private func printParamRows(_ params: [String: Any], indent: String) {
    let keys = params.keys.sorted()
    var rows: [(String, String, String, String)] = []
    
    for key in keys {
        guard let param = params[key] as? [String: Any] else {
            rows.append((key, "", "", ""))
            
            continue
        }
        
        let type = param["type"] as? String ?? ""
        let required = (param["required"] as? Bool) ?? false
        let description = param["description"] as? String ?? ""
        
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

private func printReturnRows(_ returns: [String: Any], indent: String) {
    let keys = returns.keys.sorted()
    let keyWidth = keys.map { key in key.count }.max() ?? 0
    
    for key in keys {
        let type = returns[key] as? String ?? "\(returns[key] ?? "")"
        
        print("\(indent)\(key.padding(toLength: keyWidth, withPad: " ", startingAt: 0))  \(type)")
    }
}
