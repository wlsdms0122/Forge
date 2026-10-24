//
//  WorkflowLoggerTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("WorkflowLogger Tests", .exclusive(.logSink))
struct WorkflowLoggerTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("Published workflow events land in the log file in order")
    func eventsAppearInLogFile() async throws {
        // Given
        let bus = WorkflowEventBus()
        let logger = WorkflowLogger(bus: bus)
        let context = WorkflowExecutionContext(
            runID: "wf-test-1", workflowName: "router", origin: .manual)

        // When
        let records = try await LogSinkCapture.capture("wflogger-flow") { capture in
            await logger.start()
            await WorkflowExecutionState.$context.withValue(context) {
                await LogContext.$parameters.withValue(["session_id": .string("C123:1745")]) {
                    await bus.publish(WorkflowEvent(kind: .workflowStarted,
                            runID: "wf-test-1", workflowName: "router"))
                    await bus.publish(WorkflowEvent(kind: .stepCompleted,
                            runID: "wf-test-1", workflowName: "router",
                            stepID: "agent", durationMs: 120))
                    await bus.publish(WorkflowEvent(kind: .workflowCompleted,
                            runID: "wf-test-1", workflowName: "router", durationMs: 130))
                }
            }
            let records = try await capture.records(runID: "wf-test-1", awaiting: 3)
            await logger.stop()

            return records
        }

        // Then
        #expect(records.count == 3, "All three published events should be recorded")
        let started = try #require(records.first)
        #expect(started.kind == "workflow.started")
        #expect(started.payload["workflow_name"] == .string("router"))
        if case .object(let origin) = started.payload["origin"] ?? .null {
            #expect(origin["kind"] == .string("manual"))
        } else {
            Issue.record("origin should be object {kind: manual}")
        }
        #expect(
            started.parameters["session_id"] == .string("C123:1745"),
            "Caller-defined parameters are pinned into the envelope.parameters slot")
        #expect(records[1].kind == "step.completed")
        #expect(records[1].payload["step"] == .string("agent"))
        #expect(records[1].payload["duration_ms"] == .int(120))
        #expect(
            records[1].parameters["session_id"] == .string("C123:1745"),
            "Parameters follow into step.* via automatic TaskLocal fallback")
        #expect(records[2].kind == "workflow.completed")
        #expect(records[2].payload["duration_ms"] == .int(130))
    }

    @Test("workflow.started carries the input preview and length")
    func workflowStartedLogsInputPreview() async throws {
        // Given
        let bus = WorkflowEventBus()
        let logger = WorkflowLogger(bus: bus)

        // When
        let records = try await LogSinkCapture.capture("wflogger-input") { capture in
            await logger.start()
            await bus.publish(WorkflowEvent(
                    kind: .workflowStarted,
                    runID: "wf-in", workflowName: "router",
                    inputs: ["prompt": .string("hello")],
                    inputPreview: #"{"prompt":"hello"}"#, inputLen: 18))
            let records = try await capture.records(runID: "wf-in", awaiting: 1)
            await logger.stop()

            return records
        }

        // Then
        let record = try #require(records.first)
        #expect(record.kind == "workflow.started")
        #expect(record.payload["input_preview"] == .string(#"{"prompt":"hello"}"#))
        #expect(record.payload["input_len"] == .int(18))
    }

    @Test("Events published after stop() no longer flow into the log")
    func stopUnsubscribes() async throws {
        // Given
        let bus = WorkflowEventBus()
        let logger = WorkflowLogger(bus: bus)

        // When
        let (afterStart, afterStop) = try await LogSinkCapture.capture("wflogger-stop") { capture in
            await logger.start()
            await bus.publish(WorkflowEvent(
                    kind: .workflowStarted,
                    runID: "wf-A", workflowName: "x"
            ))
            let afterStart = try await capture.records(runID: "wf-A", awaiting: 1).count
            await logger.stop()
            await bus.publish(WorkflowEvent(
                    kind: .workflowCompleted,
                    runID: "wf-A", workflowName: "x"
            ))
            try await Task.sleep(for: .milliseconds(150))

            return (afterStart, capture.records(runID: "wf-A").count)
        }

        // Then
        #expect(afterStart == 1, "Events after start() should be recorded — if 0, the comparison below is meaningless")
        #expect(afterStop == afterStart, "No new events should flow in after stop()")
    }
}
