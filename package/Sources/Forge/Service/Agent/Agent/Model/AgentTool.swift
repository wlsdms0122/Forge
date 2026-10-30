//
//  AgentTool.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

enum AgentTool: Sendable, Equatable, CustomStringConvertible {
    case filesRead
    case filesWrite
    case command(CommandPattern)
    case web
    case delegate
    case schedule
    case modelContextProtocol(String)
    
    var description: String {
        switch self {
        case .filesRead:
            return "files.read"
        
        case .filesWrite:
            return "files.write"
        
        case .command(let pattern):
            return "command:\(pattern)"
        
        case .web:
            return "web"
        
        case .delegate:
            return "delegate"
        
        case .schedule:
            return "schedule"
        
        case .modelContextProtocol(let pattern):
            return "mcp:\(pattern)"
        }
    }
}
