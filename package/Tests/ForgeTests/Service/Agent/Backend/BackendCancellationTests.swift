//
//  BackendCancellationTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("BackendCancellation Tests", .exclusive(.stubURLProtocol))
struct BackendCancellationTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("cancellation mid-run is classified as cancellation, not abnormal exit")
    func claudeInFlightCancellationIsNotNonzeroExit() async throws {
        // Given
        let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-cancel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exe = directory.appendingPathComponent("fakeclaude")
        try "#!/bin/sh\nsleep 5\n".write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        let backend = ClaudeBackend(executable: exe.path)
        let agent = try Agent(model: "anthropic:m", allowed: [])
        let task = Task<BackendResponse, Error> {
            try await backend.invoke(Invocation(id: "t", agent: agent, prompt: "go"))
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        do {

        // When
            _ = try await task.value

        // Then
            Issue.record("expected a cancellation throw")
        } catch is CancellationError {
        } catch {
            Issue.record("in-flight cancel surfaced as \(type(of: error)), not CancellationError — would be mis-logged agent.nonzero_exit")
        }
    }
    
    @Test("cancellation of the openai-compatible backend follows the same classification")
    func openAICompatibleCancellationIsNotNonzeroExit() async throws {
        // Given
        StubURLProtocol.failure = URLError(.cancelled)
        defer { StubURLProtocol.failure = nil }
        let backend = OpenAICompatibleBackend(
            baseURL: URL(string: "http://localhost:11434/v1")!,
            session: StubURLProtocol.session())
        do {
            _ = try await backend.complete(
                messages: [ChatMessage(role: .user, content: "hi")],
                tools: [], model: "m", jsonMode: false)

        // Then
            Issue.record("expected a cancellation throw")
        } catch is CancellationError {
        } catch {
            Issue.record("cancelled request surfaced as \(type(of: error)), not CancellationError — would be mis-logged agent.nonzero_exit")
        }
    }
    
    // MARK: - Private
}
