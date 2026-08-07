//
//  Output.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
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

func printJSON(_ object: [String: Any]) {
    if
        let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
    }
}

func die(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data(("forge: " + message + "\n").utf8))
    exit(code)
}

package func renderResultPlain(_ dictionary: [String: Any]) -> String {
    if dictionary.isEmpty { return "(empty result)" }
    
    var lines: [String] = []
    renderResultLines(dictionary, indent: "", into: &lines)
    
    return lines.joined(separator: "\n")
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

private func renderResultLines(_ value: Any, indent: String, into lines: inout [String]) {
    if let object = value as? [String: Any] {
        for key in resultKeyOrder(object) {
            guard let entry = object[key] else { continue }
            
            if entry is [String: Any] || entry is [Any] {
                lines.append("\(indent)\(key):")
                renderResultLines(entry, indent: indent + "  ", into: &lines)
            } else {
                appendResultScalar(label: key, value: entry, indent: indent, into: &lines)
            }
        }
    } else if let array = value as? [Any] {
        for item in array {
            if item is [String: Any] || item is [Any] {
                lines.append("\(indent)-")
                renderResultLines(item, indent: indent + "  ", into: &lines)
            } else {
                lines.append("\(indent)- \(resultScalarText(item))")
            }
        }
    } else {
        lines.append("\(indent)\(resultScalarText(value))")
    }
}

private func resultKeyOrder(_ object: [String: Any]) -> [String] {
    let head = ["status", "ok"]
    let tail = ["error"]
    let rest = object.keys
        .filter { key in !head.contains(key) && !tail.contains(key) }
        .sorted()
    
    return head.filter { key in object[key] != nil }
        + rest
        + tail.filter { key in object[key] != nil }
}

private func appendResultScalar(
    label: String,
    value: Any,
    indent: String,
    into lines: inout [String]
) {
    let text = resultScalarText(value)
    
    if text.contains("\n") {
        lines.append("\(indent)\(label):")
        
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append("\(indent)  \(line)")
        }
    } else {
        lines.append("\(indent)\(label): \(text)")
    }
}

private func resultScalarText(_ value: Any) -> String {
    if value is NSNull { return "null" }
    
    if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        
        return number.stringValue
    }
    
    if var text = value as? String {
        while text.hasSuffix("\n") { text.removeLast() }
        
        return text
    }
    
    return "\(value)"
}
