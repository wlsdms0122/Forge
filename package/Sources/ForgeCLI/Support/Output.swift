//
//  Output.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Forge

func printJSON(_ value: JSONValue) {
    if
        let data = try? JSONSerialization.data(
            withJSONObject: value.jsonObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
    }
}

// The commands that read a result as Foundation's JSON objects print it
// through this.
func printJSON(_ object: [String: Any]) {
    printJSON((try? JSONValue(jsonObject: object)) ?? .object([:]))
}

// The default answer of a client command: the whole result, as JSON when the
// caller asked for it and as an indented tree otherwise. A command only writes
// its own renderer when the plain form would bury what the command is for.
func printResult(_ value: JSONValue, json: Bool) {
    if json {
        printJSON(value)
    } else {
        print(renderResultPlain(value.objectValue ?? [:]))
    }
}

// The commands that read a result as Foundation's JSON objects print it
// through this.
func printResult(_ object: [String: Any], json: Bool) {
    printResult((try? JSONValue(jsonObject: object)) ?? .object([:]), json: json)
}

func die(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data(("forge: " + message + "\n").utf8))
    exit(code)
}

package func renderResultPlain(_ object: [String: JSONValue]) -> String {
    if object.isEmpty { return "(empty result)" }
    
    var lines: [String] = []
    renderResultLines(.object(object), indent: "", into: &lines)
    
    return lines.joined(separator: "\n")
}

private func renderResultLines(_ value: JSONValue, indent: String, into lines: inout [String]) {
    switch value {
    case let .object(object):
        for key in resultKeyOrder(object) {
            guard let entry = object[key] else { continue }
            
            switch entry {
            case .object, .array:
                lines.append("\(indent)\(key):")
                renderResultLines(entry, indent: indent + "  ", into: &lines)
            
            default:
                appendResultScalar(label: key, value: entry, indent: indent, into: &lines)
            }
        }
    
    case let .array(array):
        for item in array {
            switch item {
            case .object, .array:
                lines.append("\(indent)-")
                renderResultLines(item, indent: indent + "  ", into: &lines)
            
            default:
                lines.append("\(indent)- \(item.plainText)")
            }
        }
    
    default:
        lines.append("\(indent)\(value.plainText)")
    }
}

private func resultKeyOrder(_ object: [String: JSONValue]) -> [String] {
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
    value: JSONValue,
    indent: String,
    into lines: inout [String]
) {
    let text = value.plainText
    
    if text.contains("\n") {
        lines.append("\(indent)\(label):")
        
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append("\(indent)  \(line)")
        }
    } else {
        lines.append("\(indent)\(label): \(text)")
    }
}
