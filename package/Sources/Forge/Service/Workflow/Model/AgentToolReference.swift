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
        
        case .object(let object):
            guard object.count == 1, let (key, payload) = object.first else {
                throw ProtocolError("invoke: tool object must contain exactly one key")
            }
            
            switch (key, payload) {
            case ("command", .string(let pattern)):
                do {
                    return .command(try CommandPattern(pattern))
                } catch let error as CommandPattern.ValidationError {
                    throw ProtocolError("invoke: \(error.message)")
                }
            
            case ("mcp", .string(let pattern)) where !pattern.isEmpty:
                guard pattern == "*" || pattern.contains(".") else {
                    throw ProtocolError(
                        "invoke: mcp pattern must be '*', '<server>.*', or '<server>.<tool>'"
                            + " — a bare server name matches nothing (did you mean '\(pattern).*'?)"
                    )
                }
                
                return .modelContextProtocol(pattern)
            
            default:
                throw ProtocolError("invoke: unsupported tool object '\(key)'")
            }
        
        case .string(let name):
            throw ProtocolError("invoke: unknown tool '\(name)'")
        
        default:
            throw ProtocolError("invoke: tool must be a domain string or a single-key object")
        }
    }
    
    // MARK: - Private
}
