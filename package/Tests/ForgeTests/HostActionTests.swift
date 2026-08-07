//
//  HostActionTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
import Spec
@testable import Forge

private actor Recorder {
    // MARK: - Property
    private(set) var shellRuns: [[String]] = []
    private(set) var prompts: [String] = []
    private(set) var sessions: [AgentSessionSettings] = []
    private(set) var dispatches: [(name: String?, inputs: [String: Spec.Value])] = []

    // MARK: - Initializer
    // MARK: - Public
    func recordShell(_ command: [String]) {
        shellRuns.append(command)
    }

    func recordPrompt(_ prompt: String) {
        prompts.append(prompt)
    }

    func recordSession(_ settings: AgentSessionSettings) {
        sessions.append(settings)
    }

    func recordDispatch(name: String?, inputs: [String: Spec.Value]) {
        dispatches.append((name, inputs))
    }

    // MARK: - Private
}

private struct MockShell: ShellExecuting {
    // MARK: - Property
    let recorder: Recorder
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let delaySeconds: Double

    // MARK: - Initializer
    init(
        recorder: Recorder,
        exitCode: Int32 = 0,
        stdout: String = "",
        stderr: String = "",
        delaySeconds: Double = 0
    ) {
        self.recorder = recorder
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.delaySeconds = delaySeconds
    }

    // MARK: - Public
    func run(
        executable: String,
        args: [String],
        cwd: String?,
        env: [String: String],
        stdin: String?,
        stepID: String?
    ) async throws -> ShellRunOutput {
        if delaySeconds > 0 {
            try await Task.sleep(for: .seconds(delaySeconds))
        }

        await recorder.recordShell([executable] + args + (stdin.map { ["<\($0)"] } ?? []))

        return ShellRunOutput(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    // MARK: - Private
}

private struct MockAgent: AgentServing {
    // MARK: - Property
    @TaskLocal private static var sessionOpen = false

    let recorder: Recorder
    let reply: String

    // MARK: - Initializer
    init(recorder: Recorder, reply: String = "agent-reply") {
        self.recorder = recorder
        self.reply = reply
    }

    // MARK: - Public
    func withSession(
        _ settings: AgentSessionSettings,
        body: @Sendable () async throws -> Spec.Value
    ) async throws -> Spec.Value {
        await recorder.recordSession(settings)

        return try await Self.$sessionOpen.withValue(true) {
            try await body()
        }
    }

    func send(prompt: String) async throws -> String {
        guard Self.sessionOpen else {
            throw ExecutionError("agent step has no active session — run it inside invoke")
        }

        await recorder.recordPrompt(prompt)

        return reply
    }

    // MARK: - Private
}

private struct MockDispatcher: RunDispatching {
    // MARK: - Property
    let recorder: Recorder
    let result: Spec.Value

    // MARK: - Initializer
    init(recorder: Recorder, result: Spec.Value = .object(["ok": .bool(true)])) {
        self.recorder = recorder
        self.result = result
    }

    // MARK: - Public
    func dispatch(
        name: String?,
        inline: Spec.Value?,
        inputs: [String: Spec.Value]
    ) async throws -> Spec.Value {
        await recorder.recordDispatch(name: name, inputs: inputs)

        return result
    }

    // MARK: - Private
}

private struct MockResources: ResourceReading {
    // MARK: - Property
    let files: [String: String]

    // MARK: - Initializer
    // MARK: - Public
    func read(_ relative: String) async throws -> String {
        guard let body = files[relative] else {
            throw ExecutionError("no resource '\(relative)'")
        }

        return body
    }

    func locate(_ relative: String) async throws -> String {
        guard files[relative] != nil else {
            throw ExecutionError("no resource '\(relative)'")
        }

        return "/resource-root/" + relative
    }

    // MARK: - Private
}

private struct Harness {
    // MARK: - Property
    let recorder = Recorder()
    let loader = ForgeSpec.loader()

    // MARK: - Initializer
    // MARK: - Public
    func executor(
        shell: MockShell? = nil,
        agentReply: String = "agent-reply",
        dispatchResult: Spec.Value = .object(["ok": .bool(true)]),
        files: [String: String] = [:],
        store: (any SpecStore)? = nil
    ) -> Spec.Executor {
        loader.makeExecutor(
            store: store,
            environment: ForgeHost(
                shell: shell ?? MockShell(recorder: recorder),
                agent: MockAgent(recorder: recorder, reply: agentReply),
                dispatcher: MockDispatcher(recorder: recorder, result: dispatchResult),
                resources: MockResources(files: files),
                loader: loader,
                pool: WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max),
                runID: "wf-test"
            )
        )
    }

    // MARK: - Private
}

@Suite
struct HostActionTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("a shell step runs its command once references resolve")
    func shellRunsWhenReferencesResolve() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.loader.load("""
        name: shelling
        inputs:
          who: string
        steps:
          - id: echo
            shell:
              command:
                - echo
                - { format: "hi ${who}", with: { who: { ref: inputs.who } } }
              stdin: { ref: inputs.who }
        outputs:
          result: { ref: echo }
        """)
        let sut = harness.executor(
            shell: MockShell(recorder: harness.recorder, stdout: "done\n")
        )

        // When
        let outputs = try await sut.run(spec, inputs: ["who": .string("spec")])

        // Then
        #expect(outputs["result"] == .string("done\n"))
        #expect(await harness.recorder.shellRuns == [["echo", "hi spec", "<spec"]])
    }

    @Test("a nonzero exit code is absorbed by a step that declares rescue")
    func nonzeroExitRescuesWhenStepDeclaresCatch() async throws {
        // Given — a nonzero exit is the world's failure, so rescue absorbs it
        let harness = Harness()
        let spec = try harness.loader.load("""
        name: failing-shell
        steps:
          - id: broken
            shell:
              command: [false]
            rescue:
              - id: recovery
                value: recovered
        outputs:
          result: { ref: broken }
        """)
        let sut = harness.executor(
            shell: MockShell(recorder: harness.recorder, exitCode: 1)
        )

        // When
        let outputs = try await sut.run(spec)

        // Then
        #expect(outputs["result"] == .string("recovered"))
    }

    @Test("when shell declares outputs, values are extracted from stdout")
    func outputsExtractWhenShellDeclaresThem() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.loader.load("""
        name: extracting
        steps:
          - id: probe
            shell:
              command: [probe]
              outputs:
                code: { regex: "code=(\\\\d+)", type: int }
        outputs:
          result: { ref: probe.code }
        """)
        let sut = harness.executor(
            shell: MockShell(recorder: harness.recorder, stdout: "code=42")
        )

        // When
        let outputs = try await sut.run(spec)

        // Then
        #expect(outputs["result"] == .int(42))
    }

    @Test("when shell exceeds its timeout, rescue recovers it")
    func timeoutRescuesWhenShellRunsLate() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.loader.load("""
        name: slow-shell
        steps:
          - id: slow
            shell:
              command: [sleepy]
              timeout: 0.05
            rescue:
              - id: recovery
                value: recovered
        outputs:
          result: { ref: slow }
        """)
        let sut = harness.executor(
            shell: MockShell(recorder: harness.recorder, delaySeconds: 5)
        )

        // When
        let outputs = try await sut.run(spec)

        // Then — running late is the world's failure
        #expect(outputs["result"] == .string("recovered"))
    }

    @Test("when invoke opens a session, agent steps converse over it")
    func agentSpeaksWhenInvokeOpensSession() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.loader.load("""
        name: conversing
        inputs:
          topic: string
        steps:
          - id: session
            invoke:
              model: claude:opus
              steps:
                - id: turn
                  agent: { format: "tell me about ${topic}", with: { topic: { ref: inputs.topic } } }
              output: { ref: turn }
        outputs:
          result: { ref: session }
        """)
        let sut = harness.executor(agentReply: "sure!")

        // When
        let outputs = try await sut.run(spec, inputs: ["topic": .string("specs")])

        // Then
        #expect(outputs["result"] == .string("sure!"))
        #expect(await harness.recorder.prompts == ["tell me about specs"])
        #expect(await harness.recorder.sessions.first?.model == "claude:opus")
    }

    @Test("with no open session, an agent step fails")
    func agentFailsWhenNoSessionIsOpen() async throws {
        // Given — an agent step outside invoke is an authoring error
        let harness = Harness()
        let spec = try harness.loader.load("""
        name: sessionless
        steps:
          - id: turn
            agent: "hello?"
        """)
        let sut = harness.executor()

        // When / Then
        await #expect(throws: ExecutionError.self) {
            try await sut.run(spec)
        }
    }

    @Test("when the daemon responds, dispatch delegates execution")
    func dispatchDelegatesWhenDaemonAnswers() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.loader.load("""
        name: dispatching
        inputs:
          job: string
        steps:
          - id: child
            dispatch:
              name: worker
              inputs:
                job_id: { ref: inputs.job }
        outputs:
          result: { ref: child.ok }
        """)
        let sut = harness.executor(dispatchResult: .object(["ok": .bool(true)]))

        // When
        let outputs = try await sut.run(spec, inputs: ["job": .string("j-1")])

        // Then
        #expect(outputs["result"] == .bool(true))

        let dispatched = await harness.recorder.dispatches

        #expect(dispatched.count == 1)
        #expect(dispatched.first?.name == "worker")
        #expect(dispatched.first?.inputs == ["job_id": .string("j-1")])
    }

    @Test("an invalid inline dispatch spec is rejected at load time")
    func loadRejectsWhenInlineDispatchSpecIsMalformed() {
        // Given — a broken inline target fails the load, not the run
        let harness = Harness()
        let yaml = """
        name: broken-inline
        steps:
          - id: child
            dispatch:
              spec:
                steps:
                  - id: x
                    value: ok
                    fallbck: typo
        """

        // When / Then
        #expect(throws: DecodingError.self) {
            try harness.loader.load(yaml)
        }
    }

    @Test("steps passed as data run once dynamic lowers them")
    func carriedStepsRunWhenDynamicLowersThem() async throws {
        // Given — steps arrive as data through the signature, as bot-invoke does
        let harness = Harness()
        let spec = try harness.loader.load("""
        name: composing
        inputs:
          steps: array
        steps:
          - id: x
            dynamic:
              compose:
                - { ref: inputs.steps }
        outputs:
          result: { ref: x }
        """)
        let sut = harness.executor()
        let carried = Spec.Value.array([
            .object(["id": .string("first"), "value": .string("lowered")]),
            .object(["id": .string("second"), "value": .object([
                "format": .string("${text}!"),
                "with": .object(["text": .object(["ref": .string("first")])])
            ])])
        ])

        // When
        let outputs = try await sut.run(spec, inputs: ["steps": carried])

        // Then — default output is the last lowered step's output
        #expect(outputs["result"] == .string("lowered!"))
    }

    @Test("a dynamic output sees both the enclosing scope and the fragment results")
    func dynamicOutputSeesAmbientAndFragmentResults() async throws {
        // Given — output is authored in the enclosing spec: it reads the
        // ambient scope plus the fragment's step results, even though the
        // fragment itself runs closed
        let harness = Harness()
        let spec = try harness.loader.load("""
        name: out-composing
        inputs:
          steps: array
        steps:
          - id: seed
            value: ambient
          - id: x
            dynamic:
              compose:
                - { ref: inputs.steps }
              output:
                outer: { ref: seed }
                inner: { ref: first }
        outputs:
          result: { ref: x }
        """)
        let sut = harness.executor()
        let carried = Spec.Value.array([
            .object(["id": .string("first"), "value": .string("lowered")])
        ])

        // When
        let outputs = try await sut.run(spec, inputs: ["steps": carried])

        // Then
        #expect(outputs["result"] == .object([
            "outer": .string("ambient"),
            "inner": .string("lowered")
        ]))
    }

    @Test("an output referencing an invisible head is rejected before the fragment runs")
    func dynamicOutputRejectsBeforeRunningWhenHeadIsInvisible() async throws {
        // Given — an output naming nothing visible fails before the fragment's
        // side effects run
        let harness = Harness()
        let spec = try harness.loader.load("""
        name: out-typo
        inputs:
          steps: array
        steps:
          - id: x
            dynamic:
              compose:
                - { ref: inputs.steps }
              output: { ref: nowhere }
        """)
        let sut = harness.executor()
        let carried = Spec.Value.array([
            .object(["id": .string("first"), "value": .string("lowered")])
        ])

        // When / Then
        do {
            _ = try await sut.run(spec, inputs: ["steps": carried])
            Issue.record("expected ExecutionError")
        } catch let error as ExecutionError {
            #expect(error.message.contains("nowhere"), "\(error)")
        }
    }

    @Test("a lowered step whose id claims a reserved head is rejected")
    func loweredStepsRejectWhenIdClaimsReservedHead() async throws {
        // Given — steps arriving as data pass the same gate loaded ones do; an
        // id of `run` would be silently shadowed by the context namespace
        let harness = Harness()
        let spec = try harness.loader.load("""
        name: hijacking
        inputs:
          steps: array
        steps:
          - id: x
            dynamic:
              compose:
                - { ref: inputs.steps }
        """)
        let sut = harness.executor()
        let carried = Spec.Value.array([
            .object(["id": .string("run"), "value": .string("shadowed")])
        ])

        // When / Then
        await #expect(throws: ExecutionError.self) {
            try await sut.run(spec, inputs: ["steps": carried])
        }
    }

    @Test("when the host vocabulary is extended, inline dispatch uses the same vocabulary")
    func inlineDispatchSpeaksWhenHostVocabularyExtends() throws {
        // Given — the inline body lowers through the loader this file is decoded
        // with, so a custom atom valid outside is valid inside too
        let library = try SpecLibrary.standard.asking(
            PredicateAtom(key: "ends_with") { resolved, operand, _ in
                guard case .string(let text)? = resolved else { return false }
                guard case .string(let suffix) = operand else { return false }

                return text.hasSuffix(suffix)
            }
        )
        let loader = SpecLoader(
            registry: ForgeSpec.loader().registry,
            library: library,
            contextHeads: ["origin", "run"]
        )
        let yaml = """
        name: inline-vocab
        steps:
          - id: child
            dispatch:
              spec:
                inputs:
                  title: string
                steps:
                  - id: gated
                    when:
                      { of: { ref: inputs.title }, ends_with: "!" }
                    value: ok
        """

        // When / Then
        #expect(throws: Never.self) {
            try loader.load(yaml)
        }
    }

    @Test("resource renders with values from the scope as inputs")
    func resourceRendersWhenInputsComeFromScope() async throws {
        // Given — the resource is a runtime value source: its inputs are live
        // step outputs
        let harness = Harness()
        let spec = try harness.loader.load("""
        name: templating
        steps:
          - id: axes
            value: "tech, persona"
          - id: prompt
            resource:
              content: prompt/enrich.md
              inputs:
                axes: { ref: axes }
        outputs:
          result: { ref: prompt }
        """)
        let sut = harness.executor(files: [
            "prompt/enrich.md": "# enrich\naxes: ${axes}"
        ])

        // When
        let outputs = try await sut.run(spec)

        // Then
        #expect(outputs["result"] == .string("# enrich\naxes: tech, persona"))
    }

    @Test("resource path locates the file without rendering it")
    func resourcePathLocatesWithoutRendering() async throws {
        // Given — the body holds shell syntax that is not template dialect;
        // locating must never read or render it
        let harness = Harness()
        let spec = try harness.loader.load("""
        name: locating
        steps:
          - id: script
            resource:
              path: script/run.sh
        outputs:
          where: { ref: script }
        """)
        let sut = harness.executor(files: [
            "script/run.sh": "#!/bin/sh\necho \"$PATH\""
        ])

        // When
        let outputs = try await sut.run(spec)

        // Then
        #expect(outputs["where"] == .string("/resource-root/script/run.sh"))
    }

    @Test("resource path with inputs is rejected at load")
    func resourcePathRejectsInputs() throws {
        // Given
        let harness = Harness()
        let yaml = """
        name: bad-ask
        steps:
          - id: script
            resource:
              path: script/run.sh
              inputs: { who: world }
        """

        // When / Then — a location does not render, so inputs mean nothing there
        #expect(throws: DecodingError.self) {
            try harness.loader.load(yaml)
        }
    }

    @Test("a rescue reads the shell failure as a value")
    func rescueReadsShellFailurePayload() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.loader.load("""
        name: rescued
        steps:
          - id: risky
            shell:
              command: [fail-tool]
            rescue:
              - id: why
                value:
                  code: { ref: risky.exit_code }
                  said: { ref: risky.stderr }
        outputs:
          code: { ref: risky.code }
          said: { ref: risky.said }
        """)
        let sut = harness.executor(shell: MockShell(
            recorder: harness.recorder,
            exitCode: 3,
            stderr: "boom"
        ))

        // When
        let outputs = try await sut.run(spec)

        // Then — the failure was a value inside the rescue, and the step's
        // final binding is the rescue's output, not the payload
        #expect(outputs["code"] == .int(3))
        #expect(outputs["said"] == .string("boom"))
    }

    @Test("when use names a spec, the catalog provides that spec")
    func catalogServesWhenUseNamesSpec() async throws {
        // Given
        let harness = Harness()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-spec-store-\(UUID().uuidString)")

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        try """
        name: callee
        inputs:
          base: int
        steps:
          - id: echo
            value: { ref: inputs.base }
        outputs:
          doubled: { ref: inputs.base }
        """.write(
            to: directory.appendingPathComponent("callee.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let store = SpecCatalog(directory: directory, loader: harness.loader)
        let caller = try harness.loader.load("""
        name: caller
        steps:
          - id: call
            use:
              spec: callee
              inputs:
                base: 21
        outputs:
          result: { ref: call.doubled }
        """)
        let sut = harness.executor(store: store)

        // When
        let outputs = try await sut.run(caller)

        // Then
        #expect(outputs["result"] == .int(21))
    }

    @Test("when a step runs, events flow through the bridge")
    func eventsBridgeWhenStepsRun() async throws {
        // Given
        let harness = Harness()
        let collected = Collected()
        let spec = try harness.loader.load("""
        name: observed
        steps:
          - id: fine
            value: ok
          - id: fragile
            shell:
              command: [broken]
            rescue:
              - id: recovery
                value: recovered
        """)
        let bridge = EventBridge(
            workflowID: "wf-test",
            workflowName: "observed"
        ) { event in
            await collected.append(event)
        }
        let sut = harness.loader.makeExecutor(
            observer: bridge,
            environment: ForgeHost(
                shell: MockShell(recorder: harness.recorder, exitCode: 1),
                agent: MockAgent(recorder: harness.recorder),
                dispatcher: MockDispatcher(recorder: harness.recorder),
                resources: MockResources(files: [:]),
                loader: harness.loader,
                pool: WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max),
                runID: "wf-test"
            )
        )

        // When
        _ = try await sut.run(spec)

        // Then — the failed step reports failure, then completion as rescued
        let kinds = await collected.events.map { event -> String in
            let id = event.stepID ?? "?"

            return "\(id):\(event.kind)"
        }

        #expect(kinds.contains("fine:stepCompleted"))
        #expect(kinds.contains("fragile:stepFailed"))

        let rescuedEvents = await collected.events.filter { event in
            event.stepID == "fragile" && event.kind == .stepCompleted
        }

        #expect(rescuedEvents.first?.absorbed == true)
    }
}

private actor Collected {
    // MARK: - Property
    private(set) var events: [WorkflowEvent] = []

    // MARK: - Initializer
    // MARK: - Public
    func append(_ event: WorkflowEvent) {
        events.append(event)
    }

    // MARK: - Private
}
