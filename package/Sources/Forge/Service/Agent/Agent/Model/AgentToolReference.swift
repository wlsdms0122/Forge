//
//  AgentToolReference.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum AgentToolReference {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func decode(_ value: JSONValue) throws -> AgentTool {
        switch value {
        case .string("files.read"):
            return .filesRead
        
        case .string("files.write"):
            return .filesWrite
        
        case .string("web"):
            return .web
        
        case .string("delegate"):
            return .delegate
        
        case .string("schedule"):
            return .schedule
        
        case let .object(object):
            guard object.count == 1, let (key, payload) = object.first else {
                throw AgentValidationError("a tool dictionary has exactly one key, got \(object.count)")
            }
            
            switch key {
            case "command":
                guard case let .string(pattern) = payload else {
                    throw AgentValidationError("tool `command` takes a pattern string")
                }
                
                do {
                    return .command(try CommandPattern(pattern))
                } catch let error as CommandPattern.ValidationError {
                    throw AgentValidationError(error.message)
                }
            
            case "mcp":
                guard case let .string(pattern) = payload else {
                    throw AgentValidationError("tool `mcp` takes a pattern string")
                }
                
                guard !pattern.isEmpty else {
                    throw AgentValidationError("an mcp pattern is '*', '<server>.*' or '<server>.<tool>', got ''")
                }
                
                guard pattern == "*" || pattern.contains(".") else {
                    throw AgentValidationError(
                        "an mcp pattern is '*', '<server>.*' or '<server>.<tool>', got '\(pattern)'"
                            + " — a bare server name matches nothing (did you mean '\(pattern).*'?)"
                    )
                }
                
                return .modelContextProtocol(pattern)
            
            default:
                throw AgentValidationError("unknown tool '\(key)'")
            }
        
        case let .string(name):
            throw AgentValidationError("unknown tool '\(name)'")
        
        default:
            throw AgentValidationError("a tool is a name or a dictionary of one key")
        }
    }
    
    // MARK: - Private
}
