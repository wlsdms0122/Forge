//
//  LiveHostTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
import Spec
@testable import Forge

// MARK: - Recording backend

private final class AgentRecorder: Backend, @unchecked Sendable {
    // MARK: - Property
    let invocations = OrderedCollector<Invocation>()

    // MARK: - Initializer
    // MARK: - Public
    func invoke(_ invocation: Invocation) async throws -> BackendResponse {
        invocations.append(invocation)

        return BackendResponse(
            text: "echo:\(invocation.prompt)",
            usage: nil,
            toolEvents: [],
            stdoutLength: 0,
            durationMs: 1
        )
    }

    // MARK: - Private
}

// MARK: - LiveShell

@Suite("LiveShell Tests")
struct LiveShellTests {
    // MARK: - Property
    private let sut = LiveShell()

    // MARK: - Initializer
    // MARK: - Test
    @Test("runs a process and returns its exit code and stdout")
    func runReturnsExitAndStdoutOnSuccess() async throws {
        // When
        let output = try await sut.run(
            executable: "/bin/echo",
            args: ["hello"],
            cwd: nil,
            env: [:],
            stdin: nil,
            stepID: nil
        )

        // Then
        #expect(output.exitCode == 0)
        #expect(output.stdout == "hello\n")
    }

    @Test("env is overlaid on top of the baseline")
    func envOverridesBaseline() async throws {
        // When
        let output = try await sut.run(
            executable: "/bin/sh",
            args: ["-c", "printf %s \"$LIVE_SEAM_PROBE\""],
            cwd: nil,
            env: ["LIVE_SEAM_PROBE": "seam-value"],
            stdin: nil,
            stepID: nil
        )

        // Then
        #expect(output.stdout == "seam-value")
    }

    @Test("nonzero exit is returned as-is, without judgment — judging is the action's job")
    func runReportsNonzeroExitCode() async throws {
        // When
        let output = try await sut.run(
            executable: "/bin/sh",
            args: ["-c", "echo oops >&2; exit 3"],
            cwd: nil,
            env: [:],
            stdin: nil,
            stepID: nil
        )

        // Then
        #expect(output.exitCode == 3)
        #expect(output.stderr.contains("oops"))
    }

    @Test("task cancellation kills the process — the seam's cancellation contract")
    func cancellationKillsProcess() async throws {
        // Given
        let sut = self.sut
        let started = ContinuousClock.now
        let task = Task {
            try await sut.run(
                executable: "/bin/sleep",
                args: ["10"],
                cwd: nil,
                env: [:],
                stdin: nil,
                stepID: nil
            )
        }

        // When
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()

        let result = await task.result

        // Then
        // The essence of the contract is "the process dies and we return quickly" — the kill
        // may surface as a throw (cancelled before spawn) or as a signal-terminated nonzero exit.
        let elapsed = ContinuousClock.now - started
        let survivedWithZeroExit = (try? result.get())?.exitCode == 0

        #expect(!survivedWithZeroExit, "a cancelled process must not survive to completion")
        #expect(elapsed < .seconds(8), "after cancellation, must return quickly without waiting for process exit")
    }
}

// MARK: - LiveAgent

@Suite("LiveAgent Tests")
struct LiveAgentTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("withSession opens a session bound to the task, and send speaks through it")
    func sendSpeaksThroughAmbientSession() async throws {
        // Given
        let recorder = AgentRecorder()
        let sut = LiveAgent(executor: Executor(backend: recorder))
        let settings = AgentSessionSettings(model: "claude:probe")

        // When
        let reply = try await sut.withSession(settings) {
            .string(try await sut.send(prompt: "hello"))
        }

        // Then
        #expect(reply == .string("echo:hello"))
        #expect(recorder.invocations.elements.first?.agent.model.displayName == "claude:probe")
    }

    @Test("send without a session throws as an author error")
    func sendThrowsWithoutSession() async throws {
        // Given
        let sut = LiveAgent(executor: Executor(backend: StubBackend()))

        // When / Then
        await #expect(throws: ProtocolError.self) {
            _ = try await sut.send(prompt: "hello")
        }
    }

    @Test("share_session reuses the outer session")
    func shareSessionReusesAmbientSession() async throws {
        // Given
        let recorder = AgentRecorder()
        let sut = LiveAgent(executor: Executor(backend: recorder))
        let outer = AgentSessionSettings(model: "claude:outer")
        let inner = AgentSessionSettings(shareSession: true)

        // When
        _ = try await sut.withSession(outer) {
            try await sut.withSession(inner) {
                .string(try await sut.send(prompt: "inner"))
            }
        }

        // Then
        #expect(recorder.invocations.elements.first?.agent.model.displayName == "claude:outer")
    }

    @Test("share_session without an outer session opens a new one from the carried config")
    func shareSessionOpensNewSessionWithoutAmbient() async throws {
        // Given — share_session is conditional joining, so it carries a config for the
        // case where joining fails. Without an ambient session, that config is used.
        let recorder = AgentRecorder()
        let sut = LiveAgent(executor: Executor(backend: recorder))
        let settings = AgentSessionSettings(model: "claude:fallback", shareSession: true)

        // When
        let reply = try await sut.withSession(settings) {
            .string(try await sut.send(prompt: "solo"))
        }

        // Then
        #expect(reply == .string("echo:solo"))
        #expect(recorder.invocations.elements.first?.agent.model.displayName == "claude:fallback")
    }

    @Test("an invalid permission_mode throws")
    func unknownPermissionModeThrows() async throws {
        // Given
        let sut = LiveAgent(executor: Executor(backend: StubBackend()))
        let settings = AgentSessionSettings(model: "claude", permissionMode: "yolo")

        // When / Then
        await #expect(throws: ProtocolError.self) {
            _ = try await sut.withSession(settings) { .null }
        }
    }
}

// MARK: - SpecWorkflowRunner

@Suite("SpecWorkflowRunner Tests")
struct SpecWorkflowRunnerTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("spec-runner")

    // MARK: - Initializer
    // MARK: - Test
    @Test("runs a program and returns a result fulfilling the outputs contract")
    func runReturnsOutputs() async throws {
        // Given
        let harness = try makeRunner(catalog: [
            "hello": """
            name: hello
            inputs:
              msg:
                type: string
            steps:
              - id: greet
                value: { format: "hi ${msg}", with: { msg: { ref: inputs.msg } } }
            outputs:
              text: { ref: greet }
            """
        ])
        let program = try await harness.store.spec(named: "hello")

        // When
        let result = try await harness.dispatch(
            program: program,
            name: "hello",
            inputs: ["msg": .string("there")]
        )

        // Then
        #expect(result.status == .ok)
        #expect(result.workflowName == "hello")
        #expect(result.outputs["text"] == .string("hi there"))
    }

    @Test("a shell step runs over the live seam")
    func shellStepRunsThroughLiveSeam() async throws {
        // Given
        let harness = try makeRunner(catalog: [
            "say": """
            name: say
            steps:
              - id: say
                shell:
                  command: ["/bin/echo", "ok"]
            outputs:
              out: { ref: say }
            """
        ])
        let program = try await harness.store.spec(named: "say")

        // When
        let result = try await harness.dispatch(program: program, name: "say")

        // Then
        #expect(result.status == .ok)

        guard case .string(let out)? = result.outputs["out"] else {
            Issue.record("must be a string output: \(String(describing: result.outputs["out"]))")

            return
        }

        #expect(out.contains("ok"))
    }

    @Test("invoke/agent steps run over the agent seam")
    func agentStepRunsThroughLiveSeam() async throws {
        // Given
        let harness = try makeRunner(catalog: [
            "ask": """
            name: ask
            steps:
              - id: session
                invoke:
                  model: claude
                  steps:
                    - id: q
                      agent: "hello"
            outputs:
              reply: { ref: session }
            """
        ])
        let program = try await harness.store.spec(named: "ask")

        // When
        let result = try await harness.dispatch(program: program, name: "ask")

        // Then
        #expect(result.status == .ok)
        #expect(result.outputs["reply"] == .string("echo:hello"))
    }

    @Test("a run ending in abort is reported as a work failure")
    func abortedRunMapsToWorkFailure() async throws {
        // Given
        let harness = try makeRunner(catalog: [
            "boom": """
            name: boom
            steps:
              - id: stop
                abort: "boom reason"
            """
        ])
        let program = try await harness.store.spec(named: "boom")

        // When
        let result = try await harness.dispatch(program: program, name: "boom")

        // Then
        #expect(result.status == .failed)
        #expect(result.error?.kind == .work)
        #expect(result.error?.message.contains("boom reason") == true)
    }

    @Test("dispatch runs a child spec from the catalog as a new run and returns its outputs")
    func dispatchRunsChildSpec() async throws {
        // Given
        let harness = try makeRunner(
            catalog: [
                "parent": """
                name: parent
                steps:
                  - id: call
                    dispatch:
                      name: child
                      inputs:
                        msg: hello
                outputs:
                  got: { ref: call.echo }
                """,
                "child": """
                name: child
                inputs:
                  msg:
                    type: string
                steps:
                  - id: reply
                    value: { format: "child got ${msg}", with: { msg: { ref: inputs.msg } } }
                outputs:
                  echo: { ref: reply }
                """
            ],
            policy: ["cli:parent": ["parent", "child"]]
        )
        let program = try await harness.store.spec(named: "parent")

        // When
        let result = try await harness.dispatch(program: program, name: "parent")

        // Then
        #expect(result.status == .ok)
        #expect(result.outputs["got"] == .string("child got hello"))
    }

    @Test("when policy blocks it, dispatch fails and is not swallowed even by rescue")
    func policyDenialPunchesThroughRescue() async throws {
        // Given
        let harness = try makeRunner(
            catalog: [
                "parent": """
                name: parent
                steps:
                  - id: call
                    dispatch:
                      name: child
                    rescue:
                      - id: absorb
                        value: "swallowed"
                """,
                "child": """
                name: child
                steps:
                  - id: noop
                    value: ok
                """
            ],
            policy: ["cli:parent": ["parent"]]
        )
        let program = try await harness.store.spec(named: "parent")

        // When
        let result = try await harness.dispatch(program: program, name: "parent")

        // Then
        #expect(result.status == .failed)
        #expect(result.error?.kind == .fault)
    }

    @Test("a child's work failure can be swallowed by the parent's rescue")
    func childWorkFailureAbsorbedByParentRescue() async throws {
        // Given
        let harness = try makeRunner(
            catalog: [
                "parent": """
                name: parent
                steps:
                  - id: call
                    dispatch:
                      name: boom
                    rescue:
                      - id: absorb
                        value: "rescued"
                outputs:
                  got: { ref: call }
                """,
                "boom": """
                name: boom
                steps:
                  - id: stop
                    abort: "child gave up"
                """
            ],
            policy: ["cli:parent": ["parent", "boom"]]
        )
        let program = try await harness.store.spec(named: "parent")

        // When
        let result = try await harness.dispatch(program: program, name: "parent")

        // Then
        #expect(result.status == .ok)
        #expect(result.outputs["got"] == .string("rescued"))
    }

    @Test("run framing events are published — started/completed for parent and child alike")
    func runLevelEventsPublishedForParentAndChild() async throws {
        // Given
        let harness = try makeRunner(
            catalog: [
                "parent": """
                name: parent
                steps:
                  - id: call
                    dispatch:
                      name: child
                """,
                "child": """
                name: child
                steps:
                  - id: noop
                    value: ok
                """
            ],
            policy: ["cli:parent": ["parent", "child"]]
        )
        let (_, stream) = await harness.eventBus.subscribe()
        let program = try await harness.store.spec(named: "parent")

        // When
        let result = try await harness.dispatch(program: program, name: "parent")

        // Then
        #expect(result.status == .ok)

        var seen: [String] = []

        for await event in stream {
            seen.append("\(event.workflowName):\(event.kind)")

            if event.workflowName == "parent" && event.kind == .workflowCompleted { break }
        }

        #expect(seen.contains("parent:workflowStarted"))
        #expect(seen.contains("child:workflowStarted"))
        #expect(seen.contains("child:workflowCompleted"))
    }

    @Test("parallel children do not inherit the outer agent session")
    func parallelChildrenDoNotInheritAgentSession() async throws {
        // Given
        let harness = try makeRunner(catalog: [
            "fan": """
            name: fan
            steps:
              - id: session
                invoke:
                  model: claude
                  steps:
                    - id: par
                      parallel:
                        - id: t1
                          agent: "hello"
            """
        ])
        let program = try await harness.store.spec(named: "fan")

        // When
        let result = try await harness.dispatch(program: program, name: "fan")

        // Then — the parallel boundary severed the ambient session, so the child agent fails with no session
        #expect(result.status == .failed)
        #expect(result.error?.message.contains("no active agent session") == true)
    }

    @Test("directly driven runs are also registered in the pool, so cancellation reaches them")
    func directRunRegistersInPoolForCancel() async throws {
        // Given
        let harness = try makeRunner(catalog: [
            "slow": """
            name: slow
            steps:
              - id: nap
                shell:
                  command: ["/bin/sleep", "10"]
            """
        ])
        let program = try await harness.store.spec(named: "slow")
        let started = ContinuousClock.now
        let harnessLocal = harness
        let task = Task {
            try await harnessLocal.dispatch(
                program: program,
                name: "slow",
                workflowID: "wf-cancelme"
            )
        }

        // When
        try await Task.sleep(for: .milliseconds(300))

        _ = await harness.pool.cancel(workflowID: "wf-cancelme")

        let result = try await task.value

        // Then
        #expect(result.status == .failed)
        #expect(result.error?.kind == .cancelled)
        #expect(ContinuousClock.now - started < .seconds(8))
    }

    @Test("for invoke, cwd null means unset, and an empty permission_mode is an author error")
    func invokeNullCwdUnsetAndEmptyPermissionModeRejects() async throws {
        // Given
        let recorder = AgentRecorder()
        let harness = try makeRunner(
            catalog: [
                "nullcwd": """
                name: nullcwd
                inputs:
                  dir:
                    type: string
                    default: null
                steps:
                  - id: session
                    invoke:
                      model: claude
                      cwd: { ref: inputs.dir }
                      steps:
                        - id: q
                          agent: "hi"
                """,
                "emptymode": """
                name: emptymode
                steps:
                  - id: session
                    invoke:
                      model: claude
                      permission_mode: ""
                      steps:
                        - id: q
                          agent: "hi"
                """
            ],
            backend: recorder
        )

        // When
        let nullcwd = try await harness.store.spec(named: "nullcwd")
        let nullResult = try await harness.dispatch(program: nullcwd, name: "nullcwd")
        let emptymode = try await harness.store.spec(named: "emptymode")
        let emptyResult = try await harness.dispatch(program: emptymode, name: "emptymode")

        // Then — null stays "unset" as-is, while an empty string is an explicit rejection
        #expect(nullResult.status == .ok)
        #expect(recorder.invocations.elements.first?.agent.workingDirectory == nil)
        #expect(emptyResult.status == .failed)
        #expect(emptyResult.error?.message.contains("empty string") == true)
    }

    @Test("the step slot cap serializes concurrent shell execution")
    func stepSlotsSerializeShells() async throws {
        // Given
        let harness = try makeRunner(
            catalog: [
                "fanshell": """
                name: fanshell
                steps:
                  - id: par
                    parallel:
                      - id: a
                        shell:
                          command: ["/bin/sleep", "0.2"]
                      - id: b
                        shell:
                          command: ["/bin/sleep", "0.2"]
                """
            ],
            pool: WorkflowPool(maximumConcurrentSteps: 1, maximumActiveRuns: Int.max)
        )
        let program = try await harness.store.spec(named: "fanshell")
        let started = ContinuousClock.now

        // When
        let result = try await harness.dispatch(program: program, name: "fanshell")

        // Then
        #expect(result.status == .ok)
        #expect(
            ContinuousClock.now - started >= .milliseconds(350),
            "with one slot, the two shells must run serially"
        )
    }

    // MARK: - Private
    private struct Harness {
        // MARK: - Property
        let runner: SpecWorkflowRunner
        let store: SpecCatalog
        let eventBus: WorkflowEventBus
        let pool: WorkflowPool

        // MARK: - Initializer
        // MARK: - Public
        func dispatch(
            program: Spec.Program,
            name: String,
            inputs: [String: JSONValue] = [:],
            workflowID: String? = nil
        ) async throws -> WorkflowRunResult {
            try await runner.dispatch(
                program: program,
                name: name,
                inputs: inputs,
                principal: "cli:\(name)",
                origin: .manual,
                workflowID: workflowID,
                mode: .awaited
            )
        }

        // MARK: - Private
    }

    private func makeRunner(
        catalog: [String: String],
        policy: [String: [String]] = ["*": ["*"]],
        backend: (any Backend)? = nil,
        pool: WorkflowPool? = nil
    ) throws -> Harness {
        let directory = try temporary.make("catalog")

        for (name, yaml) in catalog {
            try yaml.write(
                to: directory.appendingPathComponent("\(name).yaml"),
                atomically: true,
                encoding: .utf8
            )
        }

        let store = SpecCatalog(directory: directory, loader: ForgeSpec.loader())
        let eventBus = WorkflowEventBus()
        let poolLocal = pool
            ?? WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max)
        let runner = SpecWorkflowRunner(
            catalog: store,
            eventBus: eventBus,
            policyStore: PolicyStore(seed: policy),
            pool: poolLocal,
            workRegistry: WorkRegistry(),
            tokenAuthority: TokenAuthority(),
            shell: LiveShell(),
            agent: LiveAgent(executor: Executor(backend: backend ?? EchoBackend())),
            resources: LiveResources(store: ResourceStore(directory: nil))
        )

        return Harness(runner: runner, store: store, eventBus: eventBus, pool: poolLocal)
    }
}
