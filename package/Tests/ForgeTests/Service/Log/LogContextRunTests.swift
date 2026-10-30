//
//  LogContextRunTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge


@Suite("LogContextRun Tests")
struct LogContextRunTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("A top-level run uses its own id as the trace root")
    func adoptRunTopLevelRootsAtRunID() async {
        // Given
        let adopted = await LogContext.adoptRun(runID: "wf-abc", parentRootID: nil, parentNodeID: nil) {
            [LogContext.rootID, LogContext.nodeID, LogContext.parentNodeID]
        }

        // Then
        #expect(adopted[0] == "wf-abc", "root_id(rootID) == runID")
        #expect(adopted[1] == "wf-abc", "node id(nodeID) == runID")
        #expect(adopted[2] == nil, "the root node has no parent")
    }
    
    @Test("A nested run inherits the root but keeps its own span")
    func adoptRunNestedInheritsRootKeepsOwnSpan() async {
        // Given
        let adopted = await LogContext.adoptRun(runID: "wf-child", parentRootID: "wf-root", parentNodeID: "wf-parent") {
            [LogContext.rootID, LogContext.nodeID, LogContext.parentNodeID]
        }

        // Then
        #expect(adopted[0] == "wf-root", "root_id keeps the parent tree root")
        #expect(adopted[1] == "wf-child", "node id is this run's runID")
        #expect(adopted[2] == "wf-parent", "the parent span is the parent node")
    }
    
    @Test("A top-level dispatch opens the trace at the run id")
    func topLevelDispatchRootsTraceAtRunID() async throws {
        // Given
        let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("forge-tracerun-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try workflowFile(#"""
        failing: [nonzero_exit, timeout]
        body:
          - let: x
            value: { call: { procedure: shell, arguments: { command: ["/bin/echo", "ok"] } } }
        """#, named: "echo").write(to: directory.appendingPathComponent("echo.yaml"), atomically: true, encoding: .utf8)
        let catalog = try WorkflowCatalog(directory: directory)
        let bus = WorkflowEventBus()
        let runner = WorkflowRunner(
            catalog: catalog,
            eventBus: bus,
            policyStore: PolicyStore(seed: ["cli:test": ["echo"]]),
            pool: WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max),
            workRegistry: WorkRegistry(),
            tokenAuthority: TokenAuthority(),
            capabilities: CapabilitySet(
                shell: LiveShell(),
                agent: LiveAgent(executor: AgentExecutor(backend: StubBackend("noop"))),
                resources: LiveResources(store: ResourceStore(directory: nil))
            )
        )
        let (_, stream) = await bus.subscribe()
        let workflow = try await catalog.workflow(named: "echo")
        let result = try await runner.dispatch(
            workflow, inputs: [:], principal: "cli:test", origin: .rpc,
            mode: .awaited
        )
        var started: WorkflowEvent?
        for await ev in stream where ev.kind == .workflowStarted {
            started = ev
            break
        }

        // Then
        #expect(started?.runID == result.runID)
        #expect(started?.rootID == result.runID, "top-level run: root_id(trace_id) == run_id")
    }
    
    // MARK: - Private
}
