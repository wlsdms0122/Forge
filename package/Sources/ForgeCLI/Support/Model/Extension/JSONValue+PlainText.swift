//
//  JSONValue+PlainText.swift
//  ForgeCLI
//
//  Created by JSilver on 10/25/26.
//

import Foundation
import Forge

extension JSONValue {
    // A value as a command prints it for a reader: a string without its
    // trailing newlines, a number and a boolean as JSON writes them, a
    // container as compact JSON with sorted keys.
    var plainText: String {
        switch self {
        case .null:
            return "null"
        
        case let .bool(flag):
            return flag ? "true" : "false"
        
        case let .int(number):
            return String(number)
        
        case let .double(number):
            return NSNumber(value: number).stringValue
        
        case var .string(text):
            while text.hasSuffix("\n") { text.removeLast() }
            
            return text
        
        case .array, .object:
            let data = try? JSONSerialization.data(
                withJSONObject: jsonObject,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
            
            return data.map { data in String(decoding: data, as: UTF8.self) } ?? ""
        }
    }
}
