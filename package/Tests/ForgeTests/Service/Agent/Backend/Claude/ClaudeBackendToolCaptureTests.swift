//
//  ClaudeBackendToolCaptureTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("ClaudeBackendToolCapture Tests")
struct ClaudeBackendToolCaptureTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("tool event observation continues even when allowed is empty")
    func toolEventsCapturedEvenWithEmptyAllowedTools() async throws {
        // Given
        let exe = try makeFakeClaude()
        defer { try? FileManager.default.removeItem(at: exe.deletingLastPathComponent()) }
        let backend = ClaudeBackend(executable: exe.path)
        let agent = try Agent(
            model: "claude:sonnet",
            allowed: [])

        // When
        let result = try await backend.invoke(Invocation(id: "t", agent: agent, prompt: "go"))

        // Then
        #expect(result.text == "done")
        #expect(result.toolEvents.count == 1, "actual tool_use must be captured even with empty allowedTools")
        #expect(result.toolEvents.first?.name == "bash")
        #expect(result.usage?["input_tokens"] == 5)
    }
    
    // MARK: - Private
    private func makeFakeClaude() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-toolcapture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let exe = directory.appendingPathComponent("fakeclaude")
        let script = """
        #!/bin/sh
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu1","name":"bash","input":{"command":"echo hi"}}]}}'
        echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu1","content":"hi"}]}}'
        echo '{"type":"result","result":"done","usage":{"input_tokens":5,"output_tokens":3}}'
        """
        try script.write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        
        return exe
    }
}
