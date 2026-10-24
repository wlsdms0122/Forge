//
//  ClaudeSessionEstablishedTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("ClaudeSessionEstablished Tests")
struct ClaudeSessionEstablishedTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("the session stands after a failed first turn so the next turn attaches")
    func failedFirstTurnStillEstablishesSessionSoNextTurnResumes() async throws {
        // Given
        let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-est-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let logPath = base.appendingPathComponent("argv.log").path
        let exe = try makeFailingFakeClaude(logPath: logPath)
        defer { try? FileManager.default.removeItem(at: exe.deletingLastPathComponent()) }
        let backend = ClaudeBackend(executable: exe.path)
        let agent = try Agent(
            model: "claude:sonnet",
            permissionMode: .bypass)
        let session = ClaudeSession(sessionID: "UUID-EST-1")
        do {

        // When
            _ = try await backend.invoke(Invocation(id: "t0", agent: agent, prompt: "go", session: session))

        // Then
            Issue.record("turn 0 should have thrown on nonzero exit")
        } catch is BackendNonzeroExit {
        }
        #expect(session.established, "once run has returned (regardless of exit code) the session id is claimed → established must be true")
        do {
            _ = try await backend.invoke(Invocation(id: "t1", agent: agent, prompt: "go2", session: session))
            Issue.record("turn 1 should also throw (fake always exits 1)")
        } catch is BackendNonzeroExit {
        }
        
        let logged = try String(contentsOf: URL(fileURLWithPath: logPath), encoding: .utf8)
        let lines = logged.split(separator: "\n").map(String.init)
        #expect(lines.count == 2, "both turns launch claude exactly once each — got \(lines)")
        #expect(lines[0].contains("--session-id"), "turn0 creates the session (--session-id)")
        #expect(lines[1].contains("--resume"), "turn1 resumes — got: \(lines[1])")
        #expect(!lines[1].contains("--session-id"), "if turn1 re-issues --session-id, the D3 'session exists' conflict traps the group at index 0")
    }
    
    // MARK: - Private
    private func makeFailingFakeClaude(logPath: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-established-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let exe = directory.appendingPathComponent("fakeclaude")
        let script = """
        #!/bin/sh
        echo "$@" >> "\(logPath)"
        exit 1
        """
        try script.write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        
        return exe
    }
}
