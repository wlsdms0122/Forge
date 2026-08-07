//
//  LogTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("Log Tests")
struct LogTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("Crossing the threshold pushes the first record into rotation file .1 and main starts fresh")
    func sizeBasedRotation() async throws {
        // Given
        let temporary = TemporaryDirectory("log-rotate")
        let logURL = try temporary.file("forge.log.jsonl")
        let log = Log()
        await log.setSink(logURL)
        await log.setMaxBytes(200)

        // When
        await log.append("test.one", ["marker": "first"], category: "t")
        await log.append("test.two", ["marker": "second"], category: "t")

        // Then
        let rotated = logURL.appendingPathExtension("1")
        #expect(FileManager.default.fileExists(atPath: rotated.path), "rotation file .1 must be created when the threshold is exceeded")
        let mainRaw = try String(contentsOf: logURL, encoding: .utf8)
        let rotatedRaw = try String(contentsOf: rotated, encoding: .utf8)
        #expect(rotatedRaw.contains("first"), "the first record must be pushed into rotation file .1")
        #expect(mainRaw.contains("second"), "the second record must be in the fresh main file")
        #expect(!mainRaw.contains("first"), "after rotation, main starts over empty")
    }

    @Test("With a threshold of 0, no rotation happens and writes continue in one file")
    func rotationDisabled() async throws {
        // Given
        let temporary = TemporaryDirectory("log-no-rotate")
        let logURL = try temporary.file("forge.log.jsonl")
        let log = Log()
        await log.setSink(logURL)
        await log.setMaxBytes(0)

        // When
        await log.append("test.one", ["marker": "first"], category: "t")
        await log.append("test.two", ["marker": "second"], category: "t")

        // Then
        let rotated = logURL.appendingPathExtension("1")
        #expect(!FileManager.default.fileExists(atPath: rotated.path), ".1 must not be created when rotation is disabled")
        let mainRaw = try String(contentsOf: logURL, encoding: .utf8)
        #expect(mainRaw.contains("first") && mainRaw.contains("second"), "both records must remain in the same file")
    }

    @Test("The snapshotted log context carries over intact into a detached task", .exclusive(.logSink))
    func agentEventSnapshotCrossesDetachedTaskBoundary() async throws {
        // Given
        let workflowContext = WorkflowExecutionContext(
            workflowID: "wf-context",
            workflowName: "review",
            origin: .manual)

        // When
        let records = try await LogSinkCapture.capture("log-agent-context") { capture in
            let context = await LogContext.adoptRun(
                runID: "wf-context", parentRootID: nil, parentNodeID: nil
            ) {
                await LogContext.$parameters.withValue(["ticket": .string("T-1")]) {
                    LogContext.$workflowContext.withValue(workflowContext) {
                        AgentEventLogContext.current
                    }
                }
            }
            await Task.detached {
                await AgentEventLog.tool(
                    invocationID: "invocation",
                    model: "codex",
                    turn: 0,
                    sequence: 0,
                    name: "Bash",
                    input: "pwd",
                    resultPreview: "ok",
                    isError: false,
                    context: context)
            }.value

            return capture.records(workflowID: "wf-context")
        }

        // Then
        let record = try #require(records.first)
        #expect(record.rootID == "wf-context")
        #expect(record.nodeID == "wf-context")
        #expect(record.parameters["ticket"] == .string("T-1"))
        #expect(record.payload["workflow_id"] == .string("wf-context"))
    }

    @Test("Even when the backend fails, the translated model reference remains in agent.error", .exclusive(.logSink))
    func failedInvocationLogsTranslatedModelReference() async throws {
        // Given
        let logging = LoggingHook()
        let executor = Executor(
            backends: BackendRegistry(["local": ResolvedModelFailureBackend()]),
            preHooks: [logging],
            errorHooks: [logging])
        let invocation = Invocation(
            id: "translated-failure",
            agent: try Agent(model: "local"),
            prompt: "hello")

        // When
        let records = try await LogSinkCapture.capture("log-translated-failure") { capture in
            do {
                _ = try await executor.run(invocation)
                Issue.record("backend failure should propagate")
            } catch is BackendUnavailable {}

            return capture.records(kind: "agent.error")
        }

        // Then
        let payload = try #require(records.first?.payload)
        #expect(payload["model"] == .string("local:qwen3:8b"))
        #expect(payload["model_resolution"] == .string("specific"))
    }
}

private struct ResolvedModelFailureBackend: Backend {
    func invoke(_ invocation: Invocation) async throws -> BackendResponse {
        invocation.executionContext.record(modelReference: try ModelReference(
                provider: "local", model: "qwen3:8b"))
        throw BackendUnavailable("offline")
    }
}
