//
//  CodexBackendSessionTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("CodexBackendSession Tests", .serialized, .exclusive(.logSink))
struct CodexBackendSessionTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("stores the thread even when the first turn fails so the next turn continues")
    func failedFirstTurnStillStoresThreadAndNextTurnResumes() async throws {
        // Given
        let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-session-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let logPath = base.appendingPathComponent("arguments.log").path
        let executable = try fakeCodex(logPath: logPath)
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let backend = CodexBackend(executable: executable.path)
        let agent = try Agent(model: "codex", workingDirectory: base.path)
        let session = CodexSession()
        var firstTurnFailed = false
        do {
            _ = try await backend.invoke(
                Invocation(id: "t0", agent: agent, prompt: "first", session: session))
        } catch is BackendNonzeroExit {
            firstTurnFailed = true
        }

        // Then
        #expect(firstTurnFailed)
        #expect(session.threadIdentifier == "thread-created-before-failure")
        let response = try await backend.invoke(
            Invocation(id: "t1", agent: agent, prompt: "second", session: session))
        #expect(response.text == "resumed")
        #expect(session.turnIndex == 1)
        let lines = try String(contentsOfFile: logPath, encoding: .utf8)
        .split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(!lines[0].contains("resume"))
        #expect(lines[1].contains("resume"))
        #expect(lines[1].contains("thread-created-before-failure"))
    }
    
    @Test("observed tools come solely from codex JSONL")
    func observedToolsComeFromCodexJSONLAlone() async throws {
        // Given
        let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-observed-tool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fakecodex")
        let script = #"""
        #!/bin/sh
        cat >/dev/null
        printf '%s\n' "$*" > "$(dirname "$0")/argv.txt"
        echo '{"type":"thread.started","thread_id":"observed-thread"}'
        echo '{"type":"item.completed","item":{"id":"first","type":"command_execution","command":"/bin/zsh -lc '\''echo one'\''","aggregated_output":"one","exit_code":0,"status":"completed"}}'
        echo '{"type":"item.completed","item":{"id":"second","type":"command_execution","command":"/bin/zsh -lc '\''echo two'\''","aggregated_output":"two","exit_code":0,"status":"completed"}}'
        echo '{"type":"item.completed","item":{"id":"answer","type":"agent_message","text":"done"}}'
        echo '{"type":"turn.completed","usage":{"input_tokens":3,"cached_input_tokens":2,"cache_write_input_tokens":1,"output_tokens":1}}'
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let logURL = directory.appendingPathComponent("forge.log.jsonl")
        await Log.shared.setSink(logURL)
        await Log.shared.setMaxBytes(0)
        let backend = CodexBackend(executable: executable.path)
        let agent = try Agent(
            model: "codex",
            allowed: [.command(try commandPattern(["echo", "*"]))])
        let response = try await backend.invoke(
            Invocation(id: "observed-invocation", agent: agent, prompt: "echo twice"))

        // When
        await Log.shared.setSink(nil)

        // Then
        #expect(response.text == "done")
        #expect(response.usage?["cache_read_tokens"] == 2)
        #expect(response.toolEvents.count == 2)
        #expect(response.toolEvents.allSatisfy { toolEvent in toolEvent.isError == false })
        #expect(response.toolEvents.map(\.resultPreview) == ["one", "two"])
        let argv = try String(
            contentsOfFile: directory.appendingPathComponent("argv.txt").path, encoding: .utf8)
        #expect(!argv.contains("--decision-socket"))
        #expect(!argv.contains("hooks.PreToolUse"))
        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(!log.contains("agent.tool_denied"))
        let records = log.split(separator: "\n").compactMap { line -> [String: Any]? in
            guard let data = String(line).data(using: .utf8) else { return nil }
            
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }.filter { toolEvent in (toolEvent["kind"] as? String)?.hasPrefix("agent.tool") == true }
        #expect(records.count == 2)
        #expect(records.allSatisfy { record in record["kind"] as? String == "agent.tool" })
        #expect(((records[0]["payload"] as? [String: Any])?["seq"] as? NSNumber)?.intValue == 0)
        #expect(((records[1]["payload"] as? [String: Any])?["seq"] as? NSNumber)?.intValue == 1)
    }
    
    @Test("a continued turn reports only its own share of the cumulative")
    func resumedTurnReportsOnlyItsOwnShareOfThreadCumulativeUsage() async throws {
        // Given
        let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-cumulative-usage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fakecodex")
        let script = #"""
        #!/bin/sh
        cat >/dev/null
        echo '{"type":"thread.started","thread_id":"cumulative-thread"}'
        echo '{"type":"item.completed","item":{"id":"answer","type":"agent_message","text":"done"}}'
        case " $* " in
          *" resume "*)
            echo '{"type":"turn.completed","usage":{"input_tokens":300,"cached_input_tokens":250,"output_tokens":90}}'
            ;;
          *)
            echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":30}}'
            ;;
        esac
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let backend = CodexBackend(executable: executable.path)
        let agent = try Agent(model: "codex")
        let session = CodexSession()
        let first = try await backend.invoke(
            Invocation(id: "t0", agent: agent, prompt: "first", session: session))

        // Then
        #expect(first.usage?["input_tokens"] == 20)
        #expect(first.usage?["cache_read_tokens"] == 80)
        #expect(first.usage?["output_tokens"] == 30)
        let second = try await backend.invoke(
            Invocation(id: "t1", agent: agent, prompt: "second", session: session))
        #expect(second.usage?["input_tokens"] == 30)
        #expect(second.usage?["cache_read_tokens"] == 170)
        #expect(second.usage?["output_tokens"] == 60)
    }
    
    @Test("a call without a session uses the cumulative as its own usage")
    func sessionlessInvokeKeepsCumulativeAsItsOwnUsage() async throws {
        // Given
        let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-sessionless-usage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fakecodex")
        let script = #"""
        #!/bin/sh
        cat >/dev/null
        echo '{"type":"thread.started","thread_id":"sessionless-thread"}'
        echo '{"type":"item.completed","item":{"id":"answer","type":"agent_message","text":"done"}}'
        echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":30}}'
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let backend = CodexBackend(executable: executable.path)
        let response = try await backend.invoke(
            Invocation(id: "solo", agent: Agent(model: "codex"), prompt: "hello"))

        // Then
        #expect(response.usage?["input_tokens"] == 20)
        #expect(response.usage?["cache_read_tokens"] == 80)
        #expect(response.usage?["output_tokens"] == 30)
    }
    
    @Test("even with exit code 0, an incomplete protocol fails the turn instead of passing it")
    func successfulExitWithoutCompleteProtocolFailsLoudlyAndDoesNotAdvanceTurn() async throws {
        // Given
        let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-incomplete-protocol-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fakecodex")
        let script = #"""
        #!/bin/sh
        cat >/dev/null
        echo '{"type":"thread.started","thread_id":"incomplete-thread"}'
        echo '{"type":"turn.completed","usage":{"input_tokens":1}}'
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let backend = CodexBackend(executable: executable.path)
        let session = CodexSession()
        var failedLoudly = false
        do {
            _ = try await backend.invoke(Invocation(
                    id: "incomplete", agent: Agent(model: "codex"), prompt: "hello", session: session))
        } catch is BackendProtocolViolation {
            failedLoudly = true
        }

        // Then
        #expect(failedLoudly)
        #expect(session.threadIdentifier == "incomplete-thread")
        #expect(session.turnIndex == 0)
    }
    
    @Test("broken JSON lines surface as failure even on a clean exit")
    func successfulExitWithMalformedJSONLineFailsLoudly() async throws {
        let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-malformed-protocol-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fakecodex")
        let script = #"""
        #!/bin/sh
        cat >/dev/null
        echo '{"type":"thread.started","thread_id":"malformed-thread"}'
        echo 'not-json'
        echo '{"type":"item.completed","item":{"id":"answer","type":"agent_message","text":"done"}}'
        echo '{"type":"turn.completed","usage":{"input_tokens":1}}'
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let backend = CodexBackend(executable: executable.path)
        await #expect(throws: BackendProtocolViolation.self) {
            _ = try await backend.invoke(Invocation(
                    id: "malformed", agent: Agent(model: "codex"), prompt: "hello"))
        }
    }
    
    // MARK: - Private
    private func fakeCodex(logPath: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fakecodex")
        let script = """
        #!/bin/sh
        echo "$@" >> "\(logPath)"
        cat >/dev/null
        case " $* " in
          *" resume "*)
            echo '{"type":"thread.started","thread_id":"thread-created-before-failure"}'
            echo '{"type":"item.completed","item":{"id":"a","type":"agent_message","text":"resumed"}}'
            echo '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
            exit 0
            ;;
          *)
            echo '{"type":"thread.started","thread_id":"thread-created-before-failure"}'
            echo '{"type":"turn.failed","error":{"message":"first turn failed"}}'
            exit 1
            ;;
        esac
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        
        return executable
    }
}
