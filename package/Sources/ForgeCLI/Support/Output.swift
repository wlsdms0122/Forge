//
//  Output.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
//

import Foundation

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

// The default answer of a client command: the whole result, as JSON when the
// caller asked for it and as an indented tree otherwise. A command only writes
// its own renderer when the plain form would bury what the command is for.
func printResult(_ object: [String: Any], json: Bool) {
    if json {
        printJSON(object)
    } else {
        print(renderResultPlain(object))
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
