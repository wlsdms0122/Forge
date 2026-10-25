//
//  WorkflowRunnerTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
import Warp
@testable import Forge

@Suite("WorkflowRunner Tests")
struct WorkflowRunnerTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("spec-runner")

    // MARK: - Initializer
    // MARK: - Test
    @Test("runs a procedure and returns a result with the value it returns")
    func runReturnsItsValue() async throws {
        // Given
        let harness = try makeRunner(catalog: [
            "hello": """
            parameters: [ msg: String ]
            returns: "Dictionary<String, Any>"
            result: { dictionary: [ [text, { format: "hi ${msg}", with: { msg: { ref: msg } } }] ] }
            """
        ])
        let workflow = try await harness.catalog.workflow(named: "hello")

        // When
        let result = try await harness.dispatch(
            workflow,
            inputs: ["msg": .string("there")]
        )

        // Then
        #expect(result.failure == nil)
        #expect(result.workflowName == "hello")
        #expect(result.output == ["text": "hi there"])
    }

    @Test(
        "a run's result is the value it returns as JSON, whatever its kind",
        arguments: [
            (
                "returns: Forge.Origin\nresult: { call: { procedure: origin, arguments: {} } }",
                ["kind": "manual", "id": .null]
            ),
            ("returns: \"Dictionary<String, Int>\"\nresult: { dictionary: [ [a, 1] ] }", ["a": 1]),
            ("returns: \"Array<Int>\"\nresult: [ 1, 2 ]", [1, 2]),
            ("returns: String\nresult: hi", "hi"),
            ("returns: \"String?\"\nresult: null", .null)
        ] as [(String, JSONValue)]
    )
    func runResultIsTheReturnedValue(source: String, expected: JSONValue) async throws {
        // Given
        let harness = try makeRunner(catalog: ["plain": source])
        let workflow = try await harness.catalog.workflow(named: "plain")

        // When
        let result = try await harness.dispatch(workflow)

        // Then
        #expect(result.failure == nil)
        #expect(result.output == expected)
    }

    @Test(
        "a run returning a value JSON cannot hold fails, naming what could not be written",
        arguments: [
            (
                "returns: \"() -> String\"\nresult: { closure: { returns: String, result: hi } }",
                "a procedure has no JSON form"
            ),
            (
                "returns: \"Dictionary<Hashable, Int>\"\nresult: { dictionary: [ [1, 1], [\"1\", 2] ] }",
                "two keys of a dictionary write the one JSON key '1'"
            )
        ]
    )
    func unwritableReturnFailsTheRun(source: String, message: String) async throws {
        // Given
        let harness = try makeRunner(catalog: ["plain": source])
        let workflow = try await harness.catalog.workflow(named: "plain")

        // When
        let result = try await harness.dispatch(workflow)

        // Then
        #expect(result.failure?.kind == .fault)
        #expect(result.failure?.object.type == "UnwritableValue")
        #expect(result.failure?.object.message == message)
    }

    @Test("a shell step runs over the live seam")
    func shellStepRunsThroughLiveSeam() async throws {
        // Given
        let harness = try makeRunner(catalog: [
            "say": """
            returns: "Dictionary<String, Any>"
            failing: [nonzero_exit, timeout]
            body:
              - let: say
                value: { call: { procedure: shell, arguments: { command: ["/bin/echo", "ok"] } } }
            result: { dictionary: [ [out, { ref: say }] ] }
            """
        ])
        let workflow = try await harness.catalog.workflow(named: "say")

        // When
        let result = try await harness.dispatch(workflow)

        // Then
        #expect(result.failure == nil)
        guard case let .string(out)? = result.output?.objectValue?["out"] else {
            Issue.record("must be a string: \(String(describing: result.output))")
            return
        }
        #expect(out.contains("ok"))
    }

    @Test("invoke/agent steps run over the agent seam")
    func agentStepRunsThroughLiveSeam() async throws {
        // Given
        let harness = try makeRunner(catalog: [
            "ask": """
            returns: "Dictionary<String, Any>"
            failing: anything
            body:
              - let: session
                value:
                  call:
                    procedure: invoke
                    arguments: { model: claude, body: { closure: { returns: String, result: { agent: hello } } } }
            result: { dictionary: [ [reply, { ref: session }] ] }
            """
        ])
        let workflow = try await harness.catalog.workflow(named: "ask")

        // When
        let result = try await harness.dispatch(workflow)

        // Then
        #expect(result.failure == nil)
        #expect(result.output == ["reply": "echo:hello"])
    }

    @Test("a run ending in abort is reported as a work failure")
    func abortedRunMapsToWorkFailure() async throws {
        // Given
        let harness = try makeRunner(catalog: [
            "boom": """
            failing: [aborted]
            body:
              - value: { abort: "boom reason" }
            """
        ])
        let workflow = try await harness.catalog.workflow(named: "boom")

        // When
        let result = try await harness.dispatch(workflow)

        // Then
        #expect(result.failure?.kind == .work)
        #expect(result.failure?.object.message.contains("boom reason") == true)
        #expect(result.output == nil)
    }

    @Test("a run ending in a failure of the language reports the language's name for it")
    func languageFailureKeepsItsName() async throws {
        // Given
        let harness = try makeRunner(catalog: [
            "boom": """
            failing: [aborted]
            body:
              - value: { abort: "boom reason" }
            """
        ])
        let workflow = try await harness.catalog.workflow(named: "boom")

        // When
        let sut = try await harness.dispatch(workflow)

        // Then
        #expect(sut.failure?.object.type == "aborted")
    }

    @Test("dispatch runs a child spec from the catalog as a new run and returns the value it returns")
    func dispatchRunsChildSpec() async throws {
        // Given
        let harness = try makeRunner(
            catalog: [
                "parent": """
                returns: Any
                failing: [child_run_failed, timeout]
                body:
                  - let: call
                    value: { call: { procedure: dispatch, arguments: { name: child, inputs: { dictionary: [ [msg, hello] ] } } } }
                result: { ref: call }
                """,
                "child": """
                parameters: [ msg: String ]
                returns: String
                result: { format: "child got ${msg}", with: { msg: { ref: msg } } }
                """
            ],
            policy: ["cli:parent": ["parent", "child"]]
        )
        let workflow = try await harness.catalog.workflow(named: "parent")

        // When
        let result = try await harness.dispatch(workflow)

        // Then
        #expect(result.failure == nil)
        #expect(result.output == "child got hello")
    }

    @Test("a dictionary a child returns reaches the parent with its keys as they are, which a cast reads")
    func dispatchHandsAChildDictionaryToACast() async throws {
        // Given
        let harness = try makeRunner(
            catalog: [
                "parent": """
                returns: String
                failing: [child_run_failed, timeout, cast_refused]
                body:
                  - let: call
                    value: { call: { procedure: dispatch, arguments: { name: child } } }
                  - let: echoed
                    value: { as: { of: { ref: call }, type: "Dictionary<Int, String>" } }
                result: { ref: 'echoed[1]' }
                """,
                "child": """
                returns: "Dictionary<Int, String>"
                result: { dictionary: [ [1, child said] ] }
                """
            ],
            policy: ["cli:parent": ["parent", "child"]]
        )
        let workflow = try await harness.catalog.workflow(named: "parent")

        // When
        let result = try await harness.dispatch(workflow)

        // Then
        #expect(result.failure == nil)
        #expect(result.output == "child said")
    }

    @Test("a struct a child returns reaches the parent as that struct, which a cast reads")
    func dispatchHandsAChildStructAsItself() async throws {
        // Given
        let harness = try makeRunner(
            catalog: [
                "parent": """
                returns: Int
                failing: [child_run_failed, timeout, cast_refused]
                body:
                  - let: call
                    value: { call: { procedure: dispatch, arguments: { name: child } } }
                  - let: point
                    value: { as: { of: { ref: call }, type: Point } }
                result: { ref: point.x }
                """,
                "child": """
                types:
                  Point: { struct: { x: Int } }
                procedures:
                  child:
                    access: public
                    returns: Point
                    result: { struct: { x: 1 } }
                """
            ],
            policy: ["cli:parent": ["parent", "child"]]
        )
        let workflow = try await harness.catalog.workflow(named: "parent")

        // When
        let result = try await harness.dispatch(workflow)

        // Then
        #expect(result.output == 1)
    }

    @Test("a child returning a value JSON cannot hold fails, and its parent faults")
    func dispatchOfAnUnwritableChildFaults() async throws {
        // Given
        let harness = try makeRunner(
            catalog: [
                "parent": """
                returns: Any
                failing: [child_run_failed, timeout]
                body:
                  - let: call
                    value: { call: { procedure: dispatch, arguments: { name: child } } }
                result: { ref: call }
                """,
                "child": """
                returns: "() -> String"
                result: { closure: { returns: String, result: hi } }
                """
            ],
            policy: ["cli:parent": ["parent", "child"]]
        )
        let workflow = try await harness.catalog.workflow(named: "parent")

        // When
        let result = try await harness.dispatch(workflow)

        // Then
        #expect(result.failure?.kind == .fault)
        #expect(result.failure?.object.type == "ChildRunFaulted")
        #expect(result.failure?.object.message.contains("UnwritableValue") == true)
    }

    @Test("when policy blocks it, dispatch fails and is not swallowed even by catch")
    func policyDenialPunchesThroughCatch() async throws {
        // Given
        let harness = try makeRunner(
            catalog: [
                "parent": """
                body:
                  - var: absorbed
                    type: String
                    value: ""
                  - let: call
                    value:
                      try:
                        body:
                          - value: { call: { procedure: dispatch, arguments: { name: child } } }
                        catch:
                          - set: absorbed
                            value: swallowed
                """,
                "child": """
                returns: String
                result: ok
                """
            ],
            policy: ["cli:parent": ["parent"]]
        )
        let workflow = try await harness.catalog.workflow(named: "parent")

        // When
        let result = try await harness.dispatch(workflow)

        // Then
        #expect(result.failure?.kind == .fault)
    }

    @Test("a child's work failure can be swallowed by the parent's catch")
    func childWorkFailureAbsorbedByParentCatch() async throws {
        // Given
        let harness = try makeRunner(
            catalog: [
                "parent": """
                returns: "Dictionary<String, Any>"
                body:
                  - var: got
                    type: String
                    value: ""
                  - let: call
                    value:
                      try:
                        body:
                          - value: { call: { procedure: dispatch, arguments: { name: boom } } }
                        catch:
                          - set: got
                            value: rescued
                result: { dictionary: [ [got, { ref: got }] ] }
                """,
                "boom": """
                failing: [aborted]
                body:
                  - value: { abort: "child gave up" }
                """
            ],
            policy: ["cli:parent": ["parent", "boom"]]
        )
        let workflow = try await harness.catalog.workflow(named: "parent")

        // When
        let result = try await harness.dispatch(workflow)

        // Then
        #expect(result.failure == nil)
        #expect(result.output == ["got": "rescued"])
    }

    @Test("run framing events are published — started/completed for parent and child alike")
    func runLevelEventsPublishedForParentAndChild() async throws {
        // Given
        let harness = try makeRunner(
            catalog: [
                "parent": """
                failing: [child_run_failed, timeout]
                body:
                  - value: { call: { procedure: dispatch, arguments: { name: child } } }
                """,
                "child": """
                returns: "Dictionary<String, Any>"
                result: { dictionary: [ [said, ok] ] }
                """
            ],
            policy: ["cli:parent": ["parent", "child"]]
        )
        let (_, stream) = await harness.eventBus.subscribe()
        let workflow = try await harness.catalog.workflow(named: "parent")

        // When
        let result = try await harness.dispatch(workflow)

        // Then
        #expect(result.failure == nil)
        var seen: [String] = []
        for await event in stream {
            seen.append("\(event.workflowName):\(event.kind)")
            if event.workflowName == "parent" && [.workflowCompleted, .workflowFailed].contains(event.kind) { break }
        }
        #expect(seen.contains("parent:workflowStarted"))
        #expect(seen.contains("child:workflowStarted"))
        #expect(seen.contains("child:workflowCompleted"))
    }

    @Test(
        "workflow.completed carries the value the run returned in its output, null included",
        arguments: [
            ("returns: \"Dictionary<String, Int>\"\nresult: { dictionary: [ [a, 1] ] }", ["a": 1]),
            ("returns: \"String?\"\nresult: null", .null)
        ] as [(String, JSONValue)]
    )
    func completedEventCarriesTheOutput(source: String, expected: JSONValue) async throws {
        // Given
        let harness = try makeRunner(catalog: ["plain": source])
        let (_, stream) = await harness.eventBus.subscribe()
        let workflow = try await harness.catalog.workflow(named: "plain")

        // When
        _ = try await harness.dispatch(workflow)

        // Then
        var completed: WorkflowEvent?
        for await event in stream where event.kind == .workflowCompleted {
            completed = event
            break
        }
        let sut = try #require(completed)
        #expect(sut.fields["output"] == expected)
    }

    @Test(
        "workflow.completed previews the JSON its output holds, null included",
        arguments: [
            ("returns: String\nresult: hello", "hello", 5),
            ("returns: \"Dictionary<String, Int>\"\nresult: { dictionary: [ [a, 1] ] }", #"{"a":1}"#, 7),
            ("returns: \"String?\"\nresult: null", "null", 4)
        ] as [(String, String, Int)]
    )
    func completedEventPreviewsTheOutput(source: String, preview: String, length: Int) async throws {
        // Given
        let harness = try makeRunner(catalog: ["plain": source])
        let (_, stream) = await harness.eventBus.subscribe()
        let workflow = try await harness.catalog.workflow(named: "plain")

        // When
        _ = try await harness.dispatch(workflow)

        // Then
        var completed: WorkflowEvent?
        for await event in stream where event.kind == .workflowCompleted {
            completed = event
            break
        }
        let sut = try #require(completed)
        #expect(sut.fields["output_preview"] == .string(preview))
        #expect(sut.fields["output_len"] == .int(length))
    }

    @Test("parallel pieces do not inherit the outer agent session")
    func parallelChildrenDoNotInheritAgentSession() async throws {
        // Given
        let harness = try makeRunner(catalog: [
            "fan": """
            failing: anything
            body:
              - value:
                  call:
                    procedure: invoke
                    arguments:
                      model: claude
                      body:
                        closure:
                          returns: "Dictionary<String, String>"
                          result:
                            call:
                              procedure: Standard.Concurrent.allKeyed
                              arguments:
                                - dictionary:
                                    - [t1, { closure: { returns: String, result: { agent: hello } } }]
            """
        ])
        let workflow = try await harness.catalog.workflow(named: "fan")

        // When
        let result = try await harness.dispatch(workflow)

        // Then — the fan-out severed the session, so the piece's agent turn has none
        #expect(result.failure?.object.message.contains("no active agent session") == true)
    }

    @Test("directly driven runs are also registered in the pool, so cancellation reaches them")
    func directRunRegistersInPoolForCancel() async throws {
        // Given
        let harness = try makeRunner(catalog: [
            "slow": """
            failing: [nonzero_exit, timeout]
            body:
              - value: { call: { procedure: shell, arguments: { command: ["/bin/sleep", "10"] } } }
            """
        ])
        let workflow = try await harness.catalog.workflow(named: "slow")
        let started = ContinuousClock.now
        let harnessLocal = harness
        let task = Task {
            try await harnessLocal.dispatch(
                workflow,
                runID: "wf-cancelme"
            )
        }

        // When
        try await Task.sleep(for: .milliseconds(300))
        _ = await harness.pool.cancel(runID: "wf-cancelme")
        let result = try await task.value

        // Then
        #expect(result.failure?.kind == .cancelled)
        #expect(result.failure?.object.type == "RunCancelled")
        #expect(ContinuousClock.now - started < .seconds(8))
    }

    @Test("a run whose task is cancelled reports RunCancelled")
    func taskCancelledRunReportsRunCancelled() async throws {
        // Given
        let harness = try makeRunner(
            catalog: [
                "ask": """
                returns: "Dictionary<String, Any>"
                failing: anything
                body:
                  - let: reply
                    value:
                      call:
                        procedure: invoke
                        arguments: { model: claude, body: { closure: { returns: String, result: { agent: hello } } } }
                result: { dictionary: [ [reply, { ref: reply }] ] }
                """
            ],
            backend: SleepingBackend()
        )
        let workflow = try await harness.catalog.workflow(named: "ask")
        let started = ContinuousClock.now
        let harnessLocal = harness
        let task = Task {
            try await harnessLocal.dispatch(
                workflow,
                runID: "wf-task-cancelled"
            )
        }

        // When
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        let result = try await task.value

        // Then
        #expect(result.failure?.kind == .cancelled)
        #expect(result.failure?.object.type == "RunCancelled")
        #expect(ContinuousClock.now - started < .seconds(8))
    }

    @Test("a run that meets Swift's CancellationError reports RunCancelled")
    func cancellationErrorReportsRunCancelled() async throws {
        // Given
        let harness = try makeRunner(
            catalog: [
                "ask": """
                returns: "Dictionary<String, Any>"
                failing: anything
                body:
                  - let: reply
                    value:
                      call:
                        procedure: invoke
                        arguments: { model: claude, body: { closure: { returns: String, result: { agent: hello } } } }
                result: { dictionary: [ [reply, { ref: reply }] ] }
                """
            ],
            backend: CancelledBackend()
        )
        let workflow = try await harness.catalog.workflow(named: "ask")

        // When
        let result = try await harness.dispatch(workflow)

        // Then
        #expect(result.failure?.kind == .cancelled)
        #expect(result.failure?.object.type == "RunCancelled")
    }

    @Test("for invoke, cwd null means unset, and an empty permission_mode is an author error")
    func invokeNullCwdUnsetAndEmptyPermissionModeRejects() async throws {
        // Given
        let recorder = AgentRecorder()
        let harness = try makeRunner(
            catalog: [
                "nullcwd": """
                parameters: [ dir: String? ]
                failing: anything
                body:
                  - value:
                      call:
                        procedure: invoke
                        arguments: { model: claude, cwd: { ref: dir }, body: { closure: { returns: String, result: { agent: hi } } } }
                """,
                "emptymode": """
                failing: anything
                body:
                  - value:
                      call:
                        procedure: invoke
                        arguments: { model: claude, permission_mode: "", body: { closure: { returns: String, result: { agent: hi } } } }
                """
            ],
            backend: recorder
        )

        // When
        let nullcwd = try await harness.catalog.workflow(named: "nullcwd")
        let nullResult = try await harness.dispatch(nullcwd)
        let emptymode = try await harness.catalog.workflow(named: "emptymode")
        let emptyResult = try await harness.dispatch(emptymode)

        // Then — null stays "unset" as-is, while an empty string is an explicit rejection
        #expect(nullResult.failure == nil)
        #expect(recorder.invocations.elements.first?.agent.workingDirectory == nil)
        #expect(emptyResult.failure?.object.message.contains("empty string") == true)
    }

    @Test("the step slot cap serializes concurrent shell execution")
    func stepSlotsSerializeShells() async throws {
        // Given
        let harness = try makeRunner(
            catalog: [
                "fanshell": """
                failing: [concurrent_failed]
                body:
                  - value:
                      call:
                        procedure: Standard.Concurrent.allKeyed
                        arguments:
                          - dictionary:
                              - [a, { closure: { returns: String, result: { call: { procedure: shell, arguments: { command: ["/bin/sleep", "0.2"] } } } } }]
                              - [b, { closure: { returns: String, result: { call: { procedure: shell, arguments: { command: ["/bin/sleep", "0.2"] } } } } }]
                """
            ],
            pool: WorkflowPool(maximumConcurrentSteps: 1, maximumActiveRuns: Int.max)
        )
        let workflow = try await harness.catalog.workflow(named: "fanshell")
        let started = ContinuousClock.now

        // When
        let result = try await harness.dispatch(workflow)

        // Then
        #expect(result.failure == nil)
        #expect(
            ContinuousClock.now - started >= .milliseconds(350),
            "with one slot, the two shells must run serially"
        )
    }

    // MARK: - Private
    // A backend whose call ends only by cancellation, which it meets as
    // Swift's `CancellationError`.
    private struct SleepingBackend: Backend {
        // MARK: - Property
        // MARK: - Initializer
        // MARK: - Public
        func invoke(_ invocation: AgentInvocation) async throws -> BackendResponse {
            try await Task.sleep(for: .seconds(10))

            return BackendResponse(text: "", usage: nil, toolEvents: [], stdoutLength: 0, durationMs: 1)
        }

        // MARK: - Private
    }

    // A backend whose call is cancelled underneath it, as a transport
    // reports a cancelled request.
    private struct CancelledBackend: Backend {
        // MARK: - Property
        // MARK: - Initializer
        // MARK: - Public
        func invoke(_ invocation: AgentInvocation) async throws -> BackendResponse {
            throw CancellationError()
        }

        // MARK: - Private
    }

    private struct Harness {
        // MARK: - Property
        let runner: WorkflowRunner
        let catalog: WorkflowCatalog
        let eventBus: WorkflowEventBus
        let pool: WorkflowPool

        // MARK: - Initializer
        // MARK: - Public
        func dispatch(
            _ workflow: Workflow,
            inputs: [String: JSONValue] = [:],
            runID: String? = nil
        ) async throws -> WorkflowRunResult {
            try await runner.dispatch(
                workflow,
                inputs: inputs,
                principal: "cli:\(workflow.name)",
                origin: .manual,
                runID: runID,
                mode: .awaited
            )
        }

        // MARK: - Private
    }

    private func makeRunner(
        catalog sources: [String: String],
        policy: [String: [String]] = ["*": ["*"]],
        backend: (any Backend)? = nil,
        pool: WorkflowPool? = nil
    ) throws -> Harness {
        let directory = try temporary.make("catalog")

        for (name, yaml) in sources {
            // A source declaring types beside its procedure is a whole file.
            try (yaml.hasPrefix("types:") ? yaml : workflowFile(yaml, named: name)).write(
                to: directory.appendingPathComponent("\(name).yaml"),
                atomically: true,
                encoding: .utf8
            )
        }

        let catalog = try WorkflowCatalog(directory: directory)
        let eventBus = WorkflowEventBus()
        let poolLocal = pool
            ?? WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max)
        let runner = WorkflowRunner(
            catalog: catalog,
            eventBus: eventBus,
            policyStore: PolicyStore(seed: policy),
            pool: poolLocal,
            workRegistry: WorkRegistry(),
            tokenAuthority: TokenAuthority(),
            capabilities: CapabilitySet(
                shell: LiveShell(),
                agent: LiveAgent(executor: AgentExecutor(backend: backend ?? EchoBackend())),
                resources: LiveResources(store: ResourceStore(directory: nil))
            )
        )

        return Harness(runner: runner, catalog: catalog, eventBus: eventBus, pool: poolLocal)
    }
}
