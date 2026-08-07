//
//  CodexEventStream.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum CodexEventStream {
    final class Reader: @unchecked Sendable {
        typealias CompletedToolHandler = @Sendable (_ sequence: Int, _ event: ToolEvent) -> Void
        
        // MARK: - Property
        private let lock = NSLock()
        private let completedToolHandler: CompletedToolHandler?
        
        private var threadIdentifier: String?
        private var finalText = ""
        private var toolEvents: [ToolEvent] = []
        private var usage: AgentUsage?
        private var failure: String?
        private var sawThreadStarted = false
        private var sawAgentMessage = false
        private var sawTurnCompleted = false
        private var malformedLineCount = 0
        private var indexByIdentifier: [String: Int] = [:]
        private var emittedIdentifiers = Set<String>()
        
        // MARK: - Initializer
        init(completedToolHandler: CompletedToolHandler? = nil) {
            self.completedToolHandler = completedToolHandler
        }
        
        // MARK: - Public
        func feed(frame: Data, at date: Date) {
            guard let line = String(data: frame, encoding: .utf8) else {
                lock.lock()
                malformedLineCount += 1
                lock.unlock()
                
                return
            }
            
            feed(line: line, at: date)
        }
        
        func feed(line: String, at date: Date) {
            let line = line.trimmingCharacters(in: .whitespaces)
            
            guard !line.isEmpty else { return }
            
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? String
            else {
                lock.lock()
                malformedLineCount += 1
                lock.unlock()
                
                return
            }
            
            var completedTool: (Int, ToolEvent)?
            
            lock.lock()
            
            switch type {
            case "thread.started":
                sawThreadStarted = true
                threadIdentifier = object["thread_id"] as? String
            
            case "item.started", "item.updated", "item.completed":
                if let item = object["item"] as? [String: Any] {
                    completedTool = consume(item: item, event: type, at: date)
                }
            
            case "turn.completed":
                sawTurnCompleted = true
                
                if let rawUsage = object["usage"] as? [String: Any] {
                    let parsed = AgentUsage(
                        providerValues: rawUsage.compactMapValues(Self.integer)
                    )
                    usage = parsed.isEmpty ? nil : parsed
                }
            
            case "turn.failed", "error":
                failure = Self.errorText(object)
            
            default:
                break
            }
            
            lock.unlock()
            
            if let completedTool {
                completedToolHandler?(completedTool.0, completedTool.1)
            }
        }
        
        func snapshot() -> CodexEventStreamResult {
            lock.lock()
            
            defer { lock.unlock() }
            
            return CodexEventStreamResult(
                threadIdentifier: threadIdentifier,
                finalText: finalText,
                toolEvents: toolEvents,
                usage: usage,
                failure: failure,
                sawThreadStarted: sawThreadStarted,
                sawAgentMessage: sawAgentMessage,
                sawTurnCompleted: sawTurnCompleted,
                malformedLineCount: malformedLineCount
            )
        }
        
        // MARK: - Private
        private static func isTool(_ type: String) -> Bool {
            [
                "command_execution", "file_change", "mcp_tool_call", "web_search",
                "collab_tool_call", "dynamic_tool_call", "dynamicToolCall"
            ]
            .contains(type)
        }
        
        private static func toolName(_ type: String, item: [String: Any]) -> String {
            switch type {
            case "command_execution":
                return "Bash"
            
            case "file_change":
                return "apply_patch"
            
            case "mcp_tool_call":
                let server = item["server"] as? String ?? "mcp"
                let tool = item["tool"] as? String ?? item["name"] as? String ?? "tool"
                
                return "mcp__\(server)__\(tool)"
            
            case "web_search":
                return "WebSearch"
            
            case "collab_tool_call":
                return item["tool"] as? String ?? "Agent"
            
            case "dynamic_tool_call", "dynamicToolCall":
                return item["tool"] as? String ?? item["name"] as? String ?? "dynamic_tool"
            
            default:
                return type
            }
        }
        
        private static func input(_ type: String, item: [String: Any]) -> String? {
            if type == "command_execution", let command = item["command"] as? String {
                return Self.json(["command": command])
            }
            
            if type == "web_search", let query = item["query"] as? String {
                return Self.json(["query": query])
            }
            
            if let arguments = item["arguments"] { return Self.jsonValue(arguments) }
            if let changes = item["changes"] { return Self.jsonValue(changes) }
            
            return Self.json(item)
        }
        
        private static func result(_ item: [String: Any]) -> String {
            for key in [
                "aggregated_output", "output", "result", "error", "content_items",
                "contentItems", "success"
            ] {
                if let value = item[key] as? String { return value }
                if let value = item[key] { return jsonValue(value) ?? String(describing: value) }
            }
            
            return ""
        }
        
        private static func errorText(_ object: [String: Any]) -> String {
            if let message = object["message"] as? String { return message }
            
            if let error = object["error"] as? [String: Any] {
                return error["message"] as? String ?? json(error) ?? "codex turn failed"
            }
            
            return json(object) ?? "codex turn failed"
        }
        
        private static func integer(_ value: Any) -> Int? {
            if let value = value as? Int { return value }
            if let value = value as? NSNumber { return value.intValue }
            
            return nil
        }
        
        private static func json(_ value: [String: Any]) -> String? { jsonValue(value) }
        
        private static func jsonValue(_ value: Any) -> String? {
            guard
                JSONSerialization.isValidJSONObject(value),
                let data = try? JSONSerialization.data(
                    withJSONObject: value,
                    options: [.sortedKeys]
                )
            else {
                return nil
            }
            
            return String(data: data, encoding: .utf8)
        }
        
        private func consume(
            item: [String: Any],
            event: String,
            at date: Date
        ) -> (Int, ToolEvent)? {
            let itemType = item["type"] as? String ?? ""
            
            if itemType == "agent_message", event == "item.completed" {
                sawAgentMessage = true
                
                if let text = item["text"] as? String { finalText = text }
                
                return nil
            }
            
            guard Self.isTool(itemType) else { return nil }
            
            let identifier = item["id"] as? String ?? UUID().uuidString
            let index: Int
            
            if let existing = indexByIdentifier[identifier] {
                index = existing
            } else {
                var tool = ToolEvent(
                    id: identifier,
                    name: Self.toolName(itemType, item: item),
                    input: Self.input(itemType, item: item),
                    startedAt: date
                )
                
                if event == "item.completed" { tool.completedAt = date }
                
                toolEvents.append(tool)
                index = toolEvents.count - 1
                indexByIdentifier[identifier] = index
            }
            
            if event == "item.completed" {
                toolEvents[index].completedAt = date
                toolEvents[index].resultPreview = String(Self.result(item).prefix(300))
                
                let status = item["status"] as? String
                let exitCode = Self.integer(item["exit_code"] as Any)
                toolEvents[index].isError = status == "failed"
                    || (exitCode.map { exitCode in exitCode != 0 } ?? false)
                
                if emittedIdentifiers.insert(identifier).inserted {
                    return (index, toolEvents[index])
                }
            }
            
            return nil
        }
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func parse(_ stream: String) -> CodexEventStreamResult {
        let reader = Reader()
        let date = Date()
        
        for line in Lines.nonEmpty(stream) { reader.feed(line: String(line), at: date) }
        
        var result = reader.snapshot()
        
        for index in result.toolEvents.indices {
            result.toolEvents[index].startedAt = nil
            result.toolEvents[index].completedAt = nil
        }
        
        return result
    }
    
    // MARK: - Private
}
