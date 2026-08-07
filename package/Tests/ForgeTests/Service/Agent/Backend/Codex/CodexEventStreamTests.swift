//
//  CodexEventStreamTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

private final class CompletedCodexTools: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(Int, ToolEvent)] = []
    func append(sequence: Int, event: ToolEvent) {
        lock.lock(); defer { lock.unlock() }
        values.append((sequence, event))
    }
    
    var snapshot: [(Int, ToolEvent)] {
        lock.lock(); defer { lock.unlock() }
        
        return values
    }
}

@Suite("CodexEventStream Tests")
struct CodexEventStreamTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("parses thread, message, usage, and tool lifecycle")
    func parsesThreadMessageUsageAndToolLifecycle() {
        // Given
        let raw = #"""
        {"type":"thread.started","thread_id":"thread-1"}
        {"type":"item.started","item":{"id":"item-1","type":"command_execution","command":"echo hi","status":"in_progress"}}
        {"type":"item.completed","item":{"id":"item-1","type":"command_execution","command":"echo hi","aggregated_output":"hi","exit_code":0,"status":"completed"}}
        {"type":"item.completed","item":{"id":"item-2","type":"agent_message","text":"done"}}
        {"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":2,"cache_write_input_tokens":1,"output_tokens":3,"reasoning_output_tokens":4}}
        """#
        let parsed = CodexEventStream.parse(raw)

        // Then
        #expect(parsed.threadIdentifier == "thread-1")
        #expect(parsed.finalText == "done")
        #expect(parsed.usage?["input_tokens"] == 8)
        #expect(parsed.usage?["cache_read_tokens"] == 2)
        #expect(parsed.usage?["cache_write_tokens"] == 1)
        #expect(parsed.usage?["reasoning_output_tokens"] == 4)
        #expect(parsed.toolEvents.count == 1)
        #expect(parsed.toolEvents.first?.name == "Bash")
        #expect(parsed.toolEvents.first?.resultPreview == "hi")
        #expect(parsed.toolEvents.first?.isError == false)
        #expect(parsed.sawThreadStarted)
        #expect(parsed.sawAgentMessage)
        #expect(parsed.sawTurnCompleted)
        #expect(parsed.malformedLineCount == 0)
    }
    
    @Test("accepts unknown events, counting only broken lines")
    func countsMalformedProtocolLinesWithoutRejectingUnknownEvents() {
        // Given
        let parsed = CodexEventStream.parse(#"""
        not-json
        {"type":"future.event","value":1}
        """#)

        // Then
        #expect(parsed.malformedLineCount == 1)
    }
    
    @Test("parses failure messages")
    func parsesFailureMessage() {
        // Given
        let parsed = CodexEventStream.parse(
        #"{"type":"turn.failed","error":{"message":"model overloaded"}}"#)

        // Then
        #expect(parsed.failure == "model overloaded")
    }
    
    @Test("completed tools are emitted exactly once during a read")
    func emitsEachCompletedToolOnceWhileReading() {
        // Given
        let completed = CompletedCodexTools()
        let reader = CodexEventStream.Reader { sequence, event in
            completed.append(sequence: sequence, event: event)
        }
        
        let now = Date()
        reader.feed(
            line: #"{"type":"item.started","item":{"id":"item-1","type":"command_execution","command":"pwd"}}"#,
            at: now)
        reader.feed(
            line: #"{"type":"item.completed","item":{"id":"item-1","type":"command_execution","command":"pwd","aggregated_output":"/tmp","status":"completed"}}"#,
            at: now)
        reader.feed(
            line: #"{"type":"item.completed","item":{"id":"item-1","type":"command_execution","command":"pwd","aggregated_output":"/tmp","status":"completed"}}"#,
            at: now)

        // Then
        #expect(completed.snapshot.count == 1)
        #expect(completed.snapshot.first?.0 == 0)
        #expect(completed.snapshot.first?.1.resultPreview == "/tmp")
    }
    
    @Test("parses dynamic tool calls of the current codex surface")
    func parsesDynamicToolCallFromCurrentCodexSurface() {
        // Given
        let parsed = CodexEventStream.parse(
        #"{"type":"item.completed","item":{"id":"dynamic-1","type":"dynamic_tool_call","tool":"exec","arguments":{"command":"pwd"},"output":"/tmp","status":"completed"}}"#)

        // Then
        #expect(parsed.toolEvents.count == 1)
        #expect(parsed.toolEvents.first?.name == "exec")
        #expect(parsed.toolEvents.first?.input?.contains("pwd") == true)
        #expect(parsed.toolEvents.first?.resultPreview == "/tmp")
    }
    
    // MARK: - Private
}
