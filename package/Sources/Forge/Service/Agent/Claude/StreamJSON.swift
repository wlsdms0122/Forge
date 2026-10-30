//
//  StreamJSON.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum StreamJSON {
    final class Reader: @unchecked Sendable {
        // MARK: - Property
        private let lock = NSLock()
        
        private var resultLineText = ""
        private var lastAssistantText = ""
        private var toolEvents: [ToolEvent] = []
        private var usage: StreamUsage?
        private var byID: [String: Int] = [:]
        private var malformedLineCount = 0
        private var sawTerminalResult = false
        
        // MARK: - Initializer
        init() {
        }
        
        // MARK: - Public
        func feed(frame: Data, at now: Date) {
            guard let raw = String(data: frame, encoding: .utf8) else {
                lock.lock()
                malformedLineCount += 1
                lock.unlock()
                
                return
            }
            
            feed(line: raw, at: now)
        }
        
        func feed(line raw: String, at now: Date) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            
            guard !line.isEmpty else { return }
            
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                lock.lock()
                malformedLineCount += 1
                lock.unlock()
                
                return
            }
            
            lock.lock()
            
            defer { lock.unlock() }
            
            switch object["type"] as? String {
            case "result":
                sawTerminalResult = true
                
                if let result = object["result"] as? String { resultLineText = result }
                
                if let rawUsage = object["usage"] as? [String: Any] {
                    usage = StreamUsage(
                        inputTokens: rawUsage["input_tokens"] as? Int,
                        outputTokens: rawUsage["output_tokens"] as? Int,
                        cacheCreationInputTokens:
                            rawUsage["cache_creation_input_tokens"] as? Int,
                        cacheReadInputTokens: rawUsage["cache_read_input_tokens"] as? Int
                    )
                }
            
            case "assistant":
                let message = object["message"] as? [String: Any] ?? [:]
                let content = message["content"] as? [[String: Any]] ?? []
                var turnText = ""
                
                for block in content {
                    let blockType = block["type"] as? String
                    
                    if blockType == "text", let text = block["text"] as? String {
                        turnText += text
                    } else if blockType == "tool_use" {
                        let inputJSON: String? = {
                            guard let input = block["input"] else { return nil }
                            
                            if
                                let data = try? JSONSerialization.data(
                                    withJSONObject: input,
                                    options: [.sortedKeys]
                                ),
                                let text = String(data: data, encoding: .utf8)
                            {
                                return text
                            }
                            
                            return String(describing: input)
                        }()
                        
                        var event = ToolEvent(
                            id: block["id"] as? String,
                            name: block["name"] as? String,
                            input: inputJSON
                        )
                        event.startedAt = now
                        toolEvents.append(event)
                        
                        if let id = event.id { byID[id] = toolEvents.count - 1 }
                    }
                }
                
                if !turnText.isEmpty {
                    lastAssistantText = turnText
                }
            
            case "user":
                let message = object["message"] as? [String: Any] ?? [:]
                let content = message["content"] as? [[String: Any]] ?? []
                
                for block in content where (block["type"] as? String) == "tool_result" {
                    guard
                        let toolUseID = block["tool_use_id"] as? String,
                        let index = byID[toolUseID]
                    else {
                        continue
                    }
                    
                    let text: String
                    
                    if let array = block["content"] as? [[String: Any]] {
                        text = array.compactMap { item -> String? in
                            guard (item["type"] as? String) == "text" else { return nil }
                            
                            return item["text"] as? String
                        }
                        .joined()
                    } else if let string = block["content"] as? String {
                        text = string
                    } else if let value = block["content"] {
                        text = String(describing: value)
                    } else {
                        text = ""
                    }
                    
                    toolEvents[index].resultPreview = String(text.prefix(300))
                    toolEvents[index].isError = (block["is_error"] as? Bool) ?? false
                    toolEvents[index].completedAt = now
                }
            
            default:
                return
            }
        }
        
        func snapshot() -> StreamParseResult {
            lock.lock()
            
            defer { lock.unlock() }
            
            let finalText = !resultLineText.isEmpty ? resultLineText : lastAssistantText
            
            return StreamParseResult(
                finalText: finalText,
                toolEvents: toolEvents,
                usage: usage,
                malformedLineCount: malformedLineCount,
                sawTerminalResult: sawTerminalResult
            )
        }
        
        // MARK: - Private
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func parse(_ raw: String) -> StreamParseResult {
        let reader = Reader()
        let now = Date()
        
        for line in Lines.nonEmpty(raw) {
            reader.feed(line: String(line), at: now)
        }
        
        let snapshot = reader.snapshot()
        let cleared = snapshot.toolEvents.map { event -> ToolEvent in
            var cleared = event
            cleared.startedAt = nil
            cleared.completedAt = nil
            
            return cleared
        }
        
        return StreamParseResult(
            finalText: snapshot.finalText,
            toolEvents: cleared,
            usage: snapshot.usage,
            malformedLineCount: snapshot.malformedLineCount,
            sawTerminalResult: snapshot.sawTerminalResult
        )
    }
    
    // MARK: - Private
}
