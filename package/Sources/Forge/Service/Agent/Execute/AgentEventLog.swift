//
//  AgentEventLog.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum AgentEventLog {
    // MARK: - Property
    private static let category = "hook.logging"
    
    // MARK: - Initializer
    // MARK: - Public
    static func translation(
        invocationID: String,
        backend: String,
        diagnostics: [AgentTranslationDiagnostic]
    ) async {
        for diagnostic in diagnostics {
            var payload: [String: Any] = [
                "id": invocationID,
                "backend": backend,
                "field": diagnostic.field,
                "message": diagnostic.message
            ]
            
            for (key, value) in LogContext.workflowContext?.asPayload ?? [:] {
                payload[key] = value
            }
            
            await Log.shared.append(
                "agent.translation_fallback",
                LogPayload(payload),
                level: .warn,
                category: category
            )
        }
    }
    
    static func tool(
        invocationID: String,
        model: String,
        turn: Int,
        sequence: Int,
        name: String?,
        input: String?,
        resultPreview: String,
        isError: Bool,
        durationMilliseconds: Int? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        context: AgentEventLogContext? = nil
    ) async {
        var payload: [String: Any] = [
            "id": invocationID,
            "model": model,
            "turn": turn,
            "seq": sequence,
            "name": name as Any? ?? NSNull(),
            "input": input as Any? ?? NSNull(),
            "result_preview": String(resultPreview.prefix(500)),
            "is_error": isError
        ]
        
        if let durationMilliseconds { payload["duration_ms"] = durationMilliseconds }
        if let startedAt { payload["started_at"] = Log.isoString(startedAt) }
        if let completedAt { payload["completed_at"] = Log.isoString(completedAt) }
        
        for (key, value) in (context?.workflow ?? LogContext.workflowContext)?.asPayload ?? [:] {
            payload[key] = value
        }
        
        await Log.shared.append(
            "agent.tool",
            LogPayload(payload),
            level: isError ? .error : .default,
            category: category,
            parameters: context?.parameters,
            rootID: context?.rootIdentifier,
            nodeID: context?.nodeIdentifier,
            parentNodeID: context?.parentNodeIdentifier,
            at: startedAt
        )
    }
    
    static func toolDenied(
        invocationID: String,
        model: String,
        turn: Int,
        sequence: Int,
        name: String?,
        input: String?,
        reason: String,
        deniedAt: Date,
        context: AgentEventLogContext
    ) async {
        var payload: [String: Any] = [
            "id": invocationID,
            "model": model,
            "turn": turn,
            "seq": sequence,
            "name": name as Any? ?? NSNull(),
            "input": input as Any? ?? NSNull(),
            "reason": reason,
            "is_error": true,
            "denied_at": Log.isoString(deniedAt)
        ]
        
        for (key, value) in context.workflow?.asPayload ?? [:] { payload[key] = value }
        
        await Log.shared.append(
            "agent.tool_denied",
            LogPayload(payload),
            level: .error,
            category: category,
            parameters: context.parameters,
            rootID: context.rootIdentifier,
            nodeID: context.nodeIdentifier,
            parentNodeID: context.parentNodeIdentifier,
            at: deniedAt
        )
    }
    
    static func turn(
        invocationID: String,
        model: String,
        turn: Int,
        output: String,
        toolCalls: Int,
        usage: AgentUsage?,
        durationMilliseconds: Int,
        startedAt: Date
    ) async {
        var payload: [String: Any] = [
            "id": invocationID,
            "model": model,
            "turn": turn,
            "out_preview": String(output.prefix(1000)),
            "tool_calls": toolCalls,
            "duration_ms": durationMilliseconds,
            "started_at": Log.isoString(startedAt),
            "usage": usage?.asDictionary as Any? ?? NSNull()
        ]
        
        for (key, value) in LogContext.workflowContext?.asPayload ?? [:] { payload[key] = value }
        
        await Log.shared.append(
            "agent.turn",
            LogPayload(payload),
            level: .default,
            category: category,
            at: startedAt
        )
    }
    
    // MARK: - Private
}
