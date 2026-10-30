//
//  JSONValue+ResultText.swift
//  ForgeCLI
//
//  Created by JSilver on 10/25/26.
//

import Foundation
import Forge

extension JSONValue {
    // The result as an indented tree: an object's keys sorted with status and ok
    // first and error last, a multi-line string under its key.
    var resultText: String {
        guard objectValue?.isEmpty == false else { return "(empty result)" }
        
        var lines: [String] = []
        appendResultLines(indent: "", into: &lines)
        
        return lines.joined(separator: "\n")
    }

    private func appendResultLines(indent: String, into lines: inout [String]) {
        switch self {
        case let .object(object):
            for key in Self.resultKeyOrder(object) {
                guard let entry = object[key] else { continue }
                
                switch entry {
                case .object, .array:
                    lines.append("\(indent)\(key):")
                    entry.appendResultLines(indent: indent + "  ", into: &lines)
                
                default:
                    entry.appendResultScalar(label: key, indent: indent, into: &lines)
                }
            }
        
        case let .array(array):
            for item in array {
                switch item {
                case .object, .array:
                    lines.append("\(indent)-")
                    item.appendResultLines(indent: indent + "  ", into: &lines)
                
                default:
                    lines.append("\(indent)- \(item.plainText)")
                }
            }
        
        default:
            lines.append("\(indent)\(plainText)")
        }
    }

    private static func resultKeyOrder(_ object: [String: JSONValue]) -> [String] {
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
        indent: String,
        into lines: inout [String]
    ) {
        let text = plainText
        
        if text.contains("\n") {
            lines.append("\(indent)\(label):")
            
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append("\(indent)  \(line)")
            }
        } else {
            lines.append("\(indent)\(label): \(text)")
        }
    }
}
