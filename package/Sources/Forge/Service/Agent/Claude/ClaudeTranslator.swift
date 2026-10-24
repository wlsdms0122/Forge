//
//  ClaudeTranslator.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct ClaudeTranslator: AgentTranslator {
    // MARK: - Property
    // MARK: - Initializer
    init() {
    }
    
    // MARK: - Public
    static func permissionMode(_ mode: PermissionMode) -> String {
        switch mode {
        case .bypass:
            return "bypassPermissions"
        
        case .safe:
            return "dontAsk"
        
        case .restrict:
            return "default"
        }
    }
    
    static func tools(_ tools: [AgentTool]) -> [String] {
        tools.flatMap { tool in
            nativeNames(tool) { pattern in
                let exactCommand = pattern.fixedTokens.map(shellWord).joined(separator: " ")
                
                guard pattern.acceptsTrailingArguments else { return ["Bash(\(exactCommand))"] }
                
                return ["Bash(\(exactCommand))", "Bash(\(exactCommand) *)"]
            }
        }
    }
    
    static func availableTools(_ tools: [AgentTool]) -> [String] {
        var seen = Set<String>()
        
        return tools
            .flatMap { tool in nativeNames(tool) { _ in ["Bash"] } }
            .filter { name in seen.insert(name).inserted }
    }
    
    func translate(_ agent: Agent) throws -> AgentTranslation<ClaudeAgentConfiguration> {
        let model = agent.model.specifiedModel
        let allowedTools = agent.allowed
        
        return AgentTranslation(
            ClaudeAgentConfiguration(
                model: model,
                workingDirectory: agent.workingDirectory,
                environment: agent.environment,
                availableTools: allowedTools.map(Self.availableTools),
                allowedTools: allowedTools.map(Self.tools),
                permissionMode: agent.permissionMode.map(Self.permissionMode)
            )
        )
    }
    
    // MARK: - Private
    private static func nativeNames(
        _ tool: AgentTool,
        commandProjection: (CommandPattern) -> [String]
    ) -> [String] {
        switch tool {
        case .filesRead:
            return ["Read", "Glob", "Grep"]
        
        case .filesWrite:
            return ["Edit", "Write", "NotebookEdit"]
        
        case .web:
            return ["WebFetch", "WebSearch"]
        
        case .delegate:
            return ["Agent", "Task", "Workflow"]
        
        case .schedule:
            return ["CronCreate", "CronList", "CronDelete", "ScheduleWakeup"]
        
        case .modelContextProtocol(let pattern):
            return [modelContextProtocolTool(pattern)]
        
        case .command(let pattern):
            return commandProjection(pattern)
        }
    }
    
    private static func shellWord(_ value: String) -> String {
        let safe = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-=,:@+"
        )
        
        if value.unicodeScalars.allSatisfy({ scalar in safe.contains(scalar) }) { return value }
        
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    
    private static func modelContextProtocolTool(_ pattern: String) -> String {
        if pattern == "*" { return "mcp__*" }
        
        return "mcp__" + pattern.replacingOccurrences(of: ".", with: "__")
    }
}
