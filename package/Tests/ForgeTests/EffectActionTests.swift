//
//  EffectActionTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
import Warp
import WarpIR
@testable import Forge

private actor Recorder {
    // MARK: - Property
    private(set) var shellRuns: [[String]] = []
    private(set) var prompts: [String] = []
    private(set) var sessions: [AgentSessionSettings] = []
    private(set) var dispatches: [(name: String?, inputs: [String: Warp.Value])] = []

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

    func recordDispatch(name: String?, inputs: [String: Warp.Value]) {
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
        body: @Sendable () async throws -> Warp.Value
    ) async throws -> Warp.Value {
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
    let result: Warp.Value

    // MARK: - Initializer
    init(recorder: Recorder, result: Warp.Value = .object(["ok": .bool(true)])) {
        self.recorder = recorder
        self.result = result
    }

    // MARK: - Public
    func dispatch(
        name: String?,
        inline: Warp.Value?,
        inputs: [String: Warp.Value]
    ) async throws -> Warp.Value {
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
        dispatchResult: Warp.Value = .object(["ok": .bool(true)]),
        files: [String: String] = [:],
        catalog: (any ProcedureCatalog)? = nil
    ) -> Warp.Executor {
        loader.language.makeExecutor(
            catalog: catalog,
            environment: ForgeEnvironment(
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
struct EffectActionTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("a shell step runs its command once references resolve")
    func shellRunsWhenReferencesResolve() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.loader.loadProcedure("""
        parameters:
          who: string
        body:
          - id: echo
            shell:
              command:
                - echo
                - { format: "hi ${who}", with: { who: { ref: who } } }
              stdin: { ref: who }
        result:
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
        let spec = try harness.loader.loadProcedure("""
        body:
          - id: broken
            attempt:
              body:
                - id: broken
                  shell:
                    command: [false]
              rescue:
                body:
                  - id: recovery
                    value: recovered
        result:
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
        let spec = try harness.loader.loadProcedure("""
        body:
          - id: probe
            shell:
              command: [probe]
              outputs:
                code: { regex: "code=(\\\\d+)", type: int }
        result:
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
        let spec = try harness.loader.loadProcedure("""
        body:
          - id: slow
            attempt:
              body:
                - id: slow
                  shell:
                    command: [sleepy]
                    timeout: 0.05
              rescue:
                body:
                  - id: recovery
                    value: recovered
        result:
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
        let spec = try harness.loader.loadProcedure("""
        parameters:
          topic: string
        body:
          - id: session
            invoke:
              model: claude:opus
              body:
                - id: turn
                  agent: { format: "tell me about ${topic}", with: { topic: { ref: topic } } }
              result: { ref: turn }
        result:
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
        let spec = try harness.loader.loadProcedure("""
        body:
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
        let spec = try harness.loader.loadProcedure("""
        parameters:
          job: string
        body:
          - id: child
            dispatch:
              name: worker
              inputs:
                job_id: { ref: job }
        result:
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
        body:
          - id: child
            dispatch:
              spec:
                body:
                  - id: x
                    value: ok
                    fallbck: typo
        """

        // When / Then
        #expect(throws: DecodingError.self) {
            try harness.loader.loadProcedure(yaml)
        }
    }

    @Test("steps passed as data run once dynamic lowers them")
    func carriedStepsRunWhenDynamicLowersThem() async throws {
        // Given — steps arrive as data through the signature, as bot-invoke does
        let harness = Harness()
        let spec = try harness.loader.loadProcedure("""
        parameters:
          steps: array
        body:
          - id: x
            dynamic:
              compose:
                - { ref: steps }
        result:
          result: { ref: x }
        """)
        let sut = harness.executor()
        let carried = Warp.Value.array([
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
        let spec = try harness.loader.loadProcedure("""
        parameters:
          steps: array
        body:
          - id: seed
            value: ambient
          - id: x
            dynamic:
              compose:
                - { ref: steps }
              result:
                outer: { ref: seed }
                inner: { ref: first }
        result:
          result: { ref: x }
        """)
        let sut = harness.executor()
        let carried = Warp.Value.array([
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
        let spec = try harness.loader.loadProcedure("""
        parameters:
          steps: array
        body:
          - id: x
            dynamic:
              compose:
                - { ref: steps }
              result: { ref: nowhere }
        """)
        let sut = harness.executor()
        let carried = Warp.Value.array([
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
        let spec = try harness.loader.loadProcedure("""
        parameters:
          steps: array
        body:
          - id: x
            dynamic:
              compose:
                - { ref: steps }
        """)
        let sut = harness.executor()
        let carried = Warp.Value.array([
            .object(["id": .string("run"), "value": .string("shadowed")])
        ])

        // When / Then
        await #expect(throws: ExecutionError.self) {
            try await sut.run(spec, inputs: ["steps": carried])
        }
    }

    @Test("when forge's vocabulary is extended, inline dispatch uses the same vocabulary")
    func inlineDispatchSpeaksWhenHostVocabularyExtends() throws {
        // Given — the inline body lowers through the loader this file is decoded
        // with, so a custom atom valid outside is valid inside too
        let loader = Loader(registry: ForgeSpec.loader().registry)
        let yaml = """
        body:
          - id: child
            dispatch:
              spec:
                parameters:
                  title: string
                body:
                  - id: gated
                    branch:
                      when: { of: { ref: title }, ends_with: "!" }
                      then:
                        body:
                          - id: taken
                            value: ok
        """

        // When / Then
        #expect(throws: Never.self) {
            try loader.loadProcedure(yaml)
        }
    }

    @Test("resource renders with values from the scope as inputs")
    func resourceRendersWhenInputsComeFromScope() async throws {
        // Given — the resource is a runtime value source: its inputs are live
        // step outputs
        let harness = Harness()
        let spec = try harness.loader.loadProcedure("""
        body:
          - id: axes
            value: "tech, persona"
          - id: prompt
            resource:
              content: prompt/enrich.md
              inputs:
                axes: { ref: axes }
        result:
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
        let spec = try harness.loader.loadProcedure("""
        body:
          - id: script
            resource:
              path: script/run.sh
        result:
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
        body:
          - id: script
            resource:
              path: script/run.sh
              inputs: { who: world }
        """

        // When / Then — a location does not render, so inputs mean nothing there
        #expect(throws: DecodingError.self) {
            try harness.loader.loadProcedure(yaml)
        }
    }

    @Test("a rescue reads the shell failure as a value")
    func rescueReadsShellFailurePayload() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.loader.loadProcedure("""
        body:
          - id: risky
            attempt:
              body:
                - id: risky
                  shell:
                    command: [fail-tool]
              rescue:
                body:
                  - id: why
                    value:
                      code: { ref: risky.exit_code }
                      said: { ref: risky.stderr }
        result:
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

    @Test("a call resolves against the modules the catalog hands to the link")
    func catalogSuppliesTheLinkSet() async throws {
        // Given
        let harness = Harness()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-spec-store-\(UUID().uuidString)")

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        try workflowFile("""
        parameters:
          base: int
        body:
          - id: echo
            value: { ref: base }
        result:
          doubled: { ref: base }
        """, named: "callee").write(
            to: directory.appendingPathComponent("callee.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let store = SpecCatalog(directory: directory, loader: harness.loader)
        let caller = try harness.loader.loadProcedure("""
        body:
          - id: call
            call:
              procedure: callee
              arguments:
                base: 21
        result:
          result: { ref: call.doubled }
        """)
        let sut = harness.executor(catalog: store)

        // When — the caller leads and the catalog is the rest of the world,
        // which is what the daemon hands to every link
        let outputs = try await sut.run(caller, beside: await store.modules())

        // Then
        #expect(outputs["result"] == .int(21))
    }

    @Test("when a step runs, events flow through the bridge")
    func eventsBridgeWhenStepsRun() async throws {
        // Given
        let harness = Harness()
        let collected = Collected()
        let spec = try harness.loader.loadProcedure("""
        body:
          - id: fine
            value: ok
          - id: fragile
            attempt:
              body:
                - id: broken
                  shell:
                    command: [broken]
              rescue:
                body:
                  - id: recovery
                    value: recovered
        """)
        let bridge = EventBridge(
            workflowID: "wf-test",
            workflowName: "observed"
        ) { event in
            await collected.append(event)
        }
        let sut = harness.loader.language.makeExecutor(
            observer: bridge,
            environment: ForgeEnvironment(
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

        // The ledger names a step by the word the spec wrote, not by the Swift
        // type behind it — the language reports the action and forge names it.
        let started = await collected.events.filter { event in
            event.kind == .stepStarted
        }

        #expect(started.first { event in event.stepID == "fine" }?.action == "value")
        #expect(started.first { event in event.stepID == "broken" }?.action == "forge.shell")
        #expect(started.first { event in event.stepID == "fragile" }?.action == "attempt")
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

private struct EndsWithQuery: Warp.Query {
    // MARK: - Property
    let selector = "ends_with"
    let signature = Signature(parameters: ["value": Parameter(type: .string)])

    // MARK: - Initializer
    // MARK: - Public
    func evaluate(
        for receiver: Warp.Value?,
        with arguments: [String: Warp.Value]
    ) throws -> Warp.Value? {
        guard case let .string(text)? = receiver else { return .bool(false) }
        guard case let .string(suffix) = arguments["value"] else { return .bool(false) }

        return .bool(text.hasSuffix(suffix))
    }

    // MARK: - Private
}
