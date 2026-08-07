//
//  JSONPath.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum JSONPath {
    enum EvalError: ForgeError, CustomStringConvertible {
        case syntax(String)
        case notFound(String)
        
        var message: String { description }
        
        var description: String {
            switch self {
            case .syntax(let detail):
                return "JSONPath syntax: \(detail)"
            
            case .notFound(let detail):
                return "JSONPath miss: \(detail)"
            }
        }
    }
    
    enum Token: Equatable {
        case root
        case field(String)
        case wildcardField
        case index(Int)
        case wildcardIndex
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func evaluate(_ expression: String, on value: JSONValue) throws -> JSONValue {
        let tokens = try tokenize(expression)
        var current: JSONValue = value
        
        for (index, token) in tokens.enumerated() {
            current = try step(current, token: token, atIndex: index, expression: expression)
        }
        
        return current
    }
    
    static func tokenize(_ expression: String) throws -> [Token] {
        let text = expression.trimmingCharacters(in: .whitespaces)
        
        guard !text.isEmpty else { throw EvalError.syntax("empty expression") }
        
        guard text.first == "$" else {
            throw EvalError.syntax("expression must start with `$` — got: \(expression)")
        }
        
        var tokens: [Token] = []
        var index = text.index(after: text.startIndex)
        
        while index < text.endIndex {
            let character = text[index]
            
            switch character {
            case ".":
                let next = text.index(after: index)
                
                guard next < text.endIndex else {
                    throw EvalError.syntax("trailing `.` in \(expression)")
                }
                
                if text[next] == "*" {
                    tokens.append(.wildcardField)
                    index = text.index(after: next)
                    
                    continue
                }
                
                var end = next
                
                while end < text.endIndex, text[end] != ".", text[end] != "[" {
                    end = text.index(after: end)
                }
                
                let name = String(text[next..<end])
                
                guard !name.isEmpty else {
                    throw EvalError.syntax("empty field name in \(expression)")
                }
                
                tokens.append(.field(name))
                index = end
            
            case "[":
                guard let close = text[index...].firstIndex(of: "]") else {
                    throw EvalError.syntax("unclosed `[` in \(expression)")
                }
                
                let inner = text[text.index(after: index)..<close]
                    .trimmingCharacters(in: .whitespaces)
                
                if inner == "*" {
                    tokens.append(.wildcardIndex)
                } else if let position = Int(inner) {
                    tokens.append(.index(position))
                } else {
                    throw EvalError.syntax(
                        "unsupported index `\(inner)` in \(expression)"
                            + " — v1 only allows integer or `*`"
                    )
                }
                
                index = text.index(after: close)
            
            default:
                throw EvalError.syntax("unexpected character `\(character)` in \(expression)")
            }
        }
        
        for (previous, current) in zip(tokens, tokens.dropFirst()) {
            let previousIsWildcard = (previous == .wildcardIndex || previous == .wildcardField)
            let currentIsField: Bool
            
            switch current {
            case .field, .wildcardField:
                currentIsField = true
            
            default:
                currentIsField = false
            }
            
            if previousIsWildcard && currentIsField {
                throw EvalError.syntax(
                    "field access after a wildcard can never match — a wildcard yields an array, "
                        + "so only `[N]`/`[*]` may follow (v1 wildcards do not map over elements): "
                        + "\(expression)"
                )
            }
        }
        
        return tokens
    }
    
    // MARK: - Private
    private static func step(
        _ value: JSONValue,
        token: Token,
        atIndex index: Int,
        expression: String
    ) throws -> JSONValue {
        switch token {
        case .root:
            return value
        
        case .field(let name):
            guard case .object(let object) = value else {
                throw EvalError.notFound(
                    "\(expression): segment[\(index)] `.\(name)` on non-object"
                )
            }
            
            guard let found = object[name] else {
                throw EvalError.notFound(
                    "\(expression): segment[\(index)] `.\(name)` not found"
                )
            }
            
            return found
        
        case .index(let position):
            guard case .array(let array) = value else {
                throw EvalError.notFound(
                    "\(expression): segment[\(index)] `[\(position)]` on non-array"
                )
            }
            
            let actual = position < 0 ? array.count + position : position
            
            guard actual >= 0, actual < array.count else {
                throw EvalError.notFound(
                    "\(expression): segment[\(index)] `[\(position)]`"
                        + " out of bounds (len=\(array.count))"
                )
            }
            
            return array[actual]
        
        case .wildcardIndex:
            guard case .array(let array) = value else {
                throw EvalError.notFound(
                    "\(expression): segment[\(index)] `[*]` on non-array"
                )
            }
            
            return .array(array)
        
        case .wildcardField:
            guard case .object(let object) = value else {
                throw EvalError.notFound(
                    "\(expression): segment[\(index)] `.*` on non-object"
                )
            }
            
            let values = object.keys.sorted().map { key in object[key]! }
            
            return .array(values)
        }
    }
}
