//
//  EffectActionTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
import Warp
import WarpYAML
@testable import Forge

@Suite
struct EffectActionTests {
    private actor Recorder {
        // MARK: - Property
        private(set) var shellRuns: [[String]] = []
        private(set) var shellSteps: [String?] = []
        private(set) var prompts: [String] = []
        private(set) var sessions: [AgentSessionSettings] = []
        private(set) var dispatches: [(name: String, inputs: [String: Warp.Value])] = []
    
        // MARK: - Initializer
        // MARK: - Public
        func recordShell(_ command: [String], step: String?) {
            shellRuns.append(command)
            shellSteps.append(step)
        }
    
        func recordPrompt(_ prompt: String) {
            prompts.append(prompt)
        }
    
        func recordSession(_ settings: AgentSessionSettings) {
            sessions.append(settings)
        }
    
        func recordDispatch(name: String, inputs: [String: Warp.Value]) {
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
    
            await recorder.recordShell([executable] + args + (stdin.map { ["<\($0)"] } ?? []), step: stepID)
    
            return ShellRunOutput(exitCode: exitCode, stdout: stdout, stderr: stderr)
        }
    
        // MARK: - Private
    }
    
    private struct MockAgent: AgentServing {
        // MARK: - Property
        @TaskLocal private static var sessionOpen = false
    
        let recorder: Recorder
        let reply: String
    
        // The exit a turn's backend ends with, where it ends nonzero.
        let exitCode: Int32?
    
        // MARK: - Initializer
        init(recorder: Recorder, reply: String = "agent-reply", exitCode: Int32? = nil) {
            self.recorder = recorder
            self.reply = reply
            self.exitCode = exitCode
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
    
            if let exitCode {
                throw BackendNonzeroExit("agent backend exited \(exitCode)", exitCode: exitCode)
            }
    
            return reply
        }
    
        // MARK: - Private
    }
    
    private struct MockDispatcher: RunDispatching {
        // MARK: - Property
        let recorder: Recorder
        let result: Warp.Value
    
        // MARK: - Initializer
        init(recorder: Recorder, result: Warp.Value = .dictionary(Value.Dictionary(["ok": .bool(true)]))) {
            self.recorder = recorder
            self.result = result
        }
    
        // MARK: - Public
        func dispatch(name: String, inputs: [String: Warp.Value]) async throws -> Warp.Value {
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
                throw ResourceError("no resource '\(relative)'")
            }
    
            return body
        }
    
        func locate(_ relative: String) async throws -> String {
            guard files[relative] != nil else {
                throw ResourceError("no resource '\(relative)'")
            }
    
            return "/resource-root/" + relative
        }
    
        // MARK: - Private
    }
    
    private struct Harness {
        // MARK: - Property
        let recorder = Recorder()
    
        var frontend: YAMLFrontend {
            get throws { try ForgeVocabulary.shipped.get().frontend }
        }
    
        // MARK: - Initializer
    
        // MARK: - Public
        func executor(
            shell: MockShell? = nil,
            agentReply: String = "agent-reply",
            agentExit: Int32? = nil,
            dispatchResult: Warp.Value = .dictionary(Value.Dictionary(["ok": .bool(true)])),
            files: [String: String] = [:],
            publish: @escaping @Sendable (WorkflowEvent) async -> Void = { _ in }
        ) throws -> Executor {
            Executor(
                environment: ForgeEnvironment(
                    capabilities: CapabilitySet(
                        shell: shell ?? MockShell(recorder: recorder),
                        agent: MockAgent(recorder: recorder, reply: agentReply, exitCode: agentExit),
                        resources: MockResources(files: files)
                    ),
                    dispatcher: MockDispatcher(recorder: recorder, result: dispatchResult),
                    pool: WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max),
                    runID: "wf-test",
                    rootID: "wf-root",
                    origin: .manual,
                    bridge: EventBridge(
                        runID: "wf-test",
                        workflowName: "observed",
                        verbs: try ForgeVocabulary.shipped.get().verbs,
                        publish: publish
                    )
                )
            )
        }
    
        // MARK: - Private
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
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("a shell step runs its command once references resolve")
    func shellRunsWhenReferencesResolve() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.frontend.workflow("""
        parameters: [ who: String ]
        returns: String
        failing: [nonzero_exit, timeout]
        body:
          - let: echo
            value:
              call:
                procedure: shell
                arguments:
                  command: [ echo, { format: "hi ${who}", with: { who: { ref: who } } } ]
                  stdin: { ref: who }
        result: { ref: echo }
        """)
        let sut = try harness.executor(
            shell: MockShell(recorder: harness.recorder, stdout: "done\n")
        )

        // When
        let returned = try await sut.run(spec, inputs: ["who": .string("spec")])

        // Then
        #expect(returned == .string("done\n"))
        #expect(await harness.recorder.shellRuns == [["echo", "hi spec", "<spec"]])
    }

    @Test("a nonzero exit code is absorbed by a try's catch")
    func nonzeroExitCatchesWhenStepDeclaresCatch() async throws {
        // Given — a nonzero exit is the world's failure, so catch absorbs it
        let harness = Harness()
        let spec = try harness.frontend.workflow("""
        returns: String
        body:
          - var: broken
            type: String
            value: ""
          - let: attempted
            value:
              try:
                body:
                  - value: { call: { procedure: shell, arguments: { command: [ "false" ] } } }
                catch:
                  - set: broken
                    value: recovered
        result: { ref: broken }
        """)
        let sut = try harness.executor(
            shell: MockShell(recorder: harness.recorder, exitCode: 1)
        )

        // When
        let returned = try await sut.run(spec)

        // Then
        #expect(returned == .string("recovered"))
    }

    @Test("extract reads named values out of a shell step's text")
    func extractReadsValuesOutOfShellText() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.frontend.workflow("""
        returns: "Dictionary<String, Any>"
        failing: [nonzero_exit, timeout, extract_refused]
        body:
          - let: probe
            value: { call: { procedure: shell, arguments: { command: [ probe ] } } }
          - let: fields
            value:
              call:
                procedure: extract
                arguments:
                  text: { ref: probe }
                  outputs: { dictionary: [ [code, { dictionary: [ [regex, "code=(\\\\d+)"], [type, int] ] }] ] }
        result: { dictionary: [ [code, { ref: 'fields["code"]' }], [raw, { ref: 'fields["_raw"]' }] ] }
        """)
        let sut = try harness.executor(
            shell: MockShell(recorder: harness.recorder, stdout: "code=42")
        )

        // When
        let fields = try ValueBridge.fields(try await sut.run(spec))

        // Then
        #expect(fields["code"] == .int(42))
        #expect(fields["raw"] == .string("code=42"))
    }

    @Test("a text that does not hold what an extraction asks fails with extract_refused, which a catch takes")
    func extractRefusalIsCaught() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.frontend.workflow("""
        returns: "Dictionary<String, Any>"
        body:
          - var: refused
            type: String
            value: ""
          - let: reading
            value:
              try:
                body:
                  - value: { call: { procedure: extract, arguments: { text: "no code here", outputs: { dictionary: [ [code, { dictionary: [ [regex, "code=(\\\\d+)"] ] }] ] } } } }
                catch:
                  - set: refused
                    value: { ref: reading.type }
        result: { dictionary: [ [refused, { ref: refused }] ] }
        """)
        let sut = try harness.executor()

        // When
        let fields = try ValueBridge.fields(try await sut.run(spec))

        // Then
        #expect(fields["refused"] == .string("extract_refused"))
    }

    @Test("an outputs dictionary that does not parse is the workflow's defect, which no catch takes")
    func extractDefectIsNotCaught() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.frontend.workflow("""
        returns: "Dictionary<String, Any>"
        body:
          - var: refused
            type: String
            value: ""
          - let: reading
            value:
              try:
                body:
                  - value: { call: { procedure: extract, arguments: { text: "code=7", outputs: { dictionary: [ [code, { dictionary: [ [regex, "code=("] ] }] ] } } } }
                catch:
                  - set: refused
                    value: { ref: reading.type }
        result: { dictionary: [ [refused, { ref: refused }] ] }
        """)
        let sut = try harness.executor()

        // When
        let error = await #expect(throws: (any Error).self) {
            try await sut.run(spec)
        }

        // Then
        #expect("\(String(describing: error))".contains("is no regular expression"))
    }

    @Test("when shell exceeds its timeout, catch recovers it")
    func timeoutCatchesWhenShellRunsLate() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.frontend.workflow("""
        returns: String
        body:
          - var: slow
            type: String
            value: ""
          - let: attempted
            value:
              try:
                body:
                  - value: { call: { procedure: shell, arguments: { command: [ sleepy ], timeout: 0.05 } } }
                catch:
                  - set: slow
                    value: recovered
        result: { ref: slow }
        """)
        let sut = try harness.executor(
            shell: MockShell(recorder: harness.recorder, delaySeconds: 5)
        )

        // When
        let returned = try await sut.run(spec)

        // Then — running late is the world's failure
        #expect(returned == .string("recovered"))
    }

    @Test("when invoke opens a session, agent steps converse over it")
    func agentSpeaksWhenInvokeOpensSession() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.frontend.workflow("""
        parameters: [ topic: String ]
        returns: String
        failing: anything
        body:
          - let: session
            value:
              call:
                procedure: invoke
                arguments:
                  model: claude:opus
                  body:
                    closure:
                      returns: String
                      result: { agent: { format: "tell me about ${topic}", with: { topic: { ref: topic } } } }
        result: { ref: session }
        """)
        let sut = try harness.executor(agentReply: "sure!")

        // When
        let returned = try await sut.run(spec, inputs: ["topic": .string("specs")])

        // Then
        #expect(returned == .string("sure!"))
        #expect(await harness.recorder.prompts == ["tell me about specs"])
        #expect(await harness.recorder.sessions.first?.model == "claude:opus")
    }

    @Test("invoke's arguments written by name in another order reach the session in the verb's order, and those left out are its defaults or null")
    func invokeSettlesItsArgumentsByName() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.frontend.workflow("""
        returns: String
        failing: anything
        result:
          call:
            procedure: invoke
            arguments:
              body:
                closure:
                  returns: String
                  result: { agent: hi }
              permission_mode: safe
              model: claude:opus
        """)
        let sut = try harness.executor(agentReply: "sure!")

        // When
        let returned = try await sut.run(spec)

        // Then
        let session = try #require(await harness.recorder.sessions.first)

        #expect(returned == .string("sure!"))
        #expect(session.model == "claude:opus")
        #expect(session.permissionMode == "safe")
        #expect(session.allowed == nil)
        #expect(session.cwd == nil)
        #expect(session.envExtra == [:])
        #expect(session.shareSession == false)
    }

    @Test("a turn the backend ends nonzero fails with nonzero_exit, as agent declares, and a catch around agent takes it")
    func agentFailureIsCaught() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.frontend.workflow("""
        returns: "Dictionary<String, Any>"
        failing: anything
        body:
          - let: session
            value:
              call:
                procedure: invoke
                arguments:
                  body:
                    closure:
                      returns: String
                      body:
                        - var: said
                          type: String
                          value: ""
                        - let: turn
                          value:
                            try:
                              body:
                                - set: said
                                  value: { agent: hello }
                              catch:
                                - set: said
                                  value: { ref: turn.type }
                      result: { ref: said }
        result: { dictionary: [ [said, { ref: session }] ] }
        """)
        let sut = try harness.executor(agentExit: 3)

        // When
        let fields = try ValueBridge.fields(try await sut.run(spec))

        // Then
        #expect(fields["said"] == .string("nonzero_exit"))
    }

    @Test("with no open session, an agent step fails")
    func agentFailsWhenNoSessionIsOpen() async throws {
        // Given — an agent step outside invoke is an authoring error
        let harness = Harness()
        let spec = try harness.frontend.workflow("""
        returns: String
        failing: [nonzero_exit]
        result: { agent: "hello?" }
        """)
        let sut = try harness.executor()

        // When / Then
        await #expect(throws: ExecutionError.self) {
            try await sut.run(spec)
        }
    }

    @Test("when the daemon responds, dispatch delegates execution")
    func dispatchDelegatesWhenDaemonAnswers() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.frontend.workflow("""
        parameters: [ job: String ]
        returns: Any
        failing: [child_run_failed, timeout]
        body:
          - let: child
            value: { call: { procedure: dispatch, arguments: { name: worker, inputs: { dictionary: [ [job_id, { ref: job }] ] } } } }
        result: { ref: child }
        """)
        let sut = try harness.executor()

        // When
        let fields = try ValueBridge.fields(try await sut.run(spec, inputs: ["job": .string("j-1")]))

        // Then
        #expect(fields["ok"] == .bool(true))
        let dispatched = await harness.recorder.dispatches
        #expect(dispatched.count == 1)
        #expect(dispatched.first?.name == "worker")
        #expect(dispatched.first?.inputs == ["job_id": .string("j-1")])
    }

    @Test("an invalid inline spec is refused when it is read, before it runs")
    func inlineRejectsWhenSpecIsMalformed() async throws {
        // Given — the inline door reads one procedure in the YAML notation
        let catalog = try WorkflowCatalog(directory: nil)
        let spec: [String: JSONValue] = ["returns": "String", "result": "ok", "fallbck": "typo"]

        // When / Then
        await #expect(throws: (any Error).self) {
            try await catalog.inline(spec)
        }
    }

    @Test("an inline spec is read as a catalog file is: a verb and a catalog workflow by short name, their arguments by name")
    func inlineLeansOnTheLibraryAndTheCatalog() async throws {
        // Given
        let harness = Harness()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "inline-leaning-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try workflowFile("""
        parameters: [ word: String ]
        returns: String
        result: { format: "said ${word}", with: { word: { ref: word } } }
        """, named: "said").write(to: directory.appendingPathComponent("said.yaml"), atomically: true, encoding: .utf8)
        let catalog = try WorkflowCatalog(directory: directory)
        let spec = try YAMLSpec.decode([String: JSONValue].self, from: Data("""
        returns: String
        failing: [nonzero_exit, timeout]
        body:
          - let: echoed
            value: { call: { procedure: shell, arguments: { command: [ echo ] } } }
          - let: spoken
            value: { call: { procedure: said, arguments: { word: hi } } }
        result: { ref: spoken }
        """.utf8))
        let sut = try harness.executor()

        // When
        let module = try await catalog.inline(spec).module
        let returned = try await sut.run(module, entry: WorkflowCatalog.inlineSigil, beside: await catalog.modules())

        // Then
        #expect(returned == .string("said hi"))
        #expect(await harness.recorder.shellRuns == [["echo"]])
    }

    @Test("resource renders with values from the scope as inputs")
    func resourceRendersWhenInputsComeFromScope() async throws {
        // Given — the resource is a runtime value source: its inputs are live
        // step outputs
        let harness = Harness()
        let spec = try harness.frontend.workflow("""
        returns: String
        body:
          - let: axes
            value: "tech, persona"
          - let: prompt
            value: { call: { procedure: resource, arguments: { content: prompt/enrich.md, inputs: { dictionary: [ [axes, { ref: axes }] ] } } } }
        result: { ref: prompt }
        """)
        let sut = try harness.executor(files: [
            "prompt/enrich.md": "# enrich\naxes: ${axes}"
        ])

        // When
        let returned = try await sut.run(spec)

        // Then
        #expect(returned == .string("# enrich\naxes: tech, persona"))
    }

    @Test("resource writes a null input as null, as format does")
    func resourceWritesANullInputAsNull() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.frontend.workflow("""
        returns: String
        body:
          - let: prompt
            value: { call: { procedure: resource, arguments: { content: prompt/enrich.md, inputs: { dictionary: [ [axes, null] ] } } } }
        result: { ref: prompt }
        """)
        let sut = try harness.executor(files: [
            "prompt/enrich.md": "axes: ${axes}"
        ])

        // When
        let returned = try await sut.run(spec)

        // Then
        #expect(returned == .string("axes: null"))
    }

    @Test("locate finds a resource file without rendering it")
    func resourcePathLocatesWithoutRendering() async throws {
        // Given — the body holds shell syntax that is not template dialect;
        // locating must never read or render it
        let harness = Harness()
        let spec = try harness.frontend.workflow("""
        returns: "Dictionary<String, Any>"
        body:
          - let: script
            value: { locate: script/run.sh }
        result: { dictionary: [ [where, { ref: script }] ] }
        """)
        let sut = try harness.executor(files: [
            "script/run.sh": "#!/bin/sh\necho \"$PATH\""
        ])

        // When
        let fields = try ValueBridge.fields(try await sut.run(spec))

        // Then
        #expect(fields["where"] == .string("/resource-root/script/run.sh"))
    }

    @Test("a catch reads the shell failure as a value")
    func catchReadsShellFailurePayload() async throws {
        // Given
        let harness = Harness()
        let spec = try harness.frontend.workflow("""
        returns: "Dictionary<String, Any>"
        body:
          - var: kind
            type: Any
          - var: code
            type: Any
          - var: said
            type: Any
          - let: risky
            value:
              try:
                body:
                  - value: { call: { procedure: shell, arguments: { command: [ fail-tool ] } } }
                catch:
                  - set: kind
                    value: { ref: risky.type }
                  - set: code
                    value: { ref: 'risky.details["exit_code"]' }
                  - set: said
                    value: { ref: 'risky.details["stderr"]' }
        result: { dictionary: [ [kind, { ref: kind }], [code, { ref: code }], [said, { ref: said }] ] }
        """)
        let sut = try harness.executor(shell: MockShell(
            recorder: harness.recorder,
            exitCode: 3,
            stderr: "boom"
        ))

        // When
        let fields = try ValueBridge.fields(try await sut.run(spec))

        // Then
        #expect(fields["kind"] == .string("nonzero_exit"))
        #expect(fields["code"] == .int(3))
        #expect(fields["said"] == .string("boom"))
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
        parameters: [ base: Int ]
        returns: "Dictionary<String, Any>"
        result: { dictionary: [ [doubled, { ref: base }] ] }
        """, named: "callee").write(
            to: directory.appendingPathComponent("callee.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let catalog = try WorkflowCatalog(directory: directory)
        let caller = try harness.frontend.workflow("""
        returns: Any
        body:
          - let: called
            value: { call: { procedure: callee, arguments: [ 21 ] } }
        result: { ref: 'called["doubled"]' }
        """)
        let sut = try harness.executor()

        // When — the caller leads and the catalog is the rest of the world,
        // which is what the daemon hands to every link
        let returned = try await sut.run(caller, beside: await catalog.modules())

        // Then
        #expect(returned == .int(21))
    }

    @Test("a call of a verb that acts, or of its native directly, is a step, named by its calling statement and acting as the verb, and the native under a verb runs for the verb's step")
    func eventsBridgeWhenStepsRun() async throws {
        // Given
        let harness = Harness()
        let collected = Collected()
        let spec = try harness.frontend.workflow("""
        returns: "Dictionary<String, Any>"
        body:
          - let: fine
            value: ok
          - let: run
            value: { call: { procedure: run } }
          - let: origin
            value: { call: { procedure: Forge.Native.origin } }
          - var: recovered
            type: String
            value: ""
          - let: fragile
            value:
              try:
                body:
                  - let: broken
                    value: { call: { procedure: shell, arguments: { command: [ broken ] } } }
                catch:
                  - set: recovered
                    value: recovered
          - let: missing
            value: { call: { procedure: resource, arguments: { content: none.txt, inputs: { dictionary: [] } } } }
        result: { dictionary: [ [fine, { ref: fine }], [recovered, { ref: recovered }] ] }
        """)
        let sut = try harness.executor(shell: MockShell(recorder: harness.recorder, exitCode: 1)) { event in
            await collected.append(event)
        }

        // When
        await #expect(throws: ResourceError.self) {
            try await sut.run(spec)
        }

        // Then
        let events = await collected.events
        let steps = events.map { event in
            "\(event.stepID ?? "?"):\(event.kind.rawValue):\(event.action ?? "")"
        }

        #expect(steps == [
            "run:step.started:Forge.run",
            "run:step.completed:",
            "origin:step.started:Forge.Native.origin",
            "origin:step.completed:",
            "broken:step.started:Forge.shell",
            "broken:step.failed:",
            "missing:step.started:Forge.resource",
            "missing:step.failed:"
        ])
        #expect(events.last?.errorMessage == "missing.Forge.resource.[1]: no resource 'none.txt'")
        #expect(await harness.recorder.shellSteps == ["broken"])
    }

    @Test(
        "a completed step previews the JSON its output holds, and has no preview where JSON cannot hold the value",
        arguments: [
            ([(key: Value.string("ok"), value: Value.bool(true))], #"{"ok":true}"#, 11),
            ([(key: Value.int(1), value: Value.int(1)), (key: Value.string("1"), value: Value.int(2))], nil, nil)
        ] as [([(key: Value, value: Value)], String?, Int?)]
    )
    func aCompletedStepPreviewsItsOutput(
        entries: [(key: Value, value: Value)],
        preview: String?,
        length: Int?
    ) async throws {
        // Given
        let harness = Harness()
        let collected = Collected()
        let spec = try harness.frontend.workflow("""
        returns: String
        failing: [child_run_failed, timeout]
        body:
          - let: child
            value: { call: { procedure: dispatch, arguments: { name: worker, inputs: { dictionary: [] } } } }
        result: done
        """)
        let sut = try harness.executor(dispatchResult: .dictionary(try Value.Dictionary(entries))) { event in
            await collected.append(event)
        }

        // When
        _ = try await sut.run(spec)

        // Then
        let completed = try #require(await collected.events.first { event in event.kind == .stepCompleted })
        #expect(completed.fields["output_preview"] == preview.map(JSONValue.string))
        #expect(completed.fields["output_len"] == length.map(JSONValue.int))
    }

    @Test("a nonzero exit a catch takes fails its step with the trace, so the rounds of a loop sharing the step differ")
    func aNonzeroExitFailsItsStepWithTheTrace() async throws {
        // Given
        let harness = Harness()
        let collected = Collected()
        let spec = try harness.frontend.workflow("""
        returns: "Dictionary<String, Any>"
        body:
          - var: recovered
            type: Int
            value: 0
          - let: rounds
            value:
              each:
                of: [ a, b ]
                as: name
                body:
                  - let: attempted
                    value:
                      try:
                        body:
                          - let: broken
                            value: { call: { procedure: shell, arguments: { command: [ "false", { ref: name } ] } } }
                        catch:
                          - set: recovered
                            value: { of: { ref: recovered }, plus: 1 }
        result: { dictionary: [ [recovered, { ref: recovered }] ] }
        """)
        let sut = try harness.executor(
            shell: MockShell(recorder: harness.recorder, exitCode: 1, stderr: "refused")
        ) { event in
            await collected.append(event)
        }

        // When
        let fields = try ValueBridge.fields(try await sut.run(spec))

        // Then
        let failed = await collected.events.filter { event in event.kind == .stepFailed }

        #expect(fields["recovered"] == .int(2))
        #expect(failed.map(\.stepID) == ["broken", "broken"])
        #expect(failed.map(\.errorMessage) == [
            "[1].rounds[0].attempted.broken.Forge.shell.[1]: shell exit 1: refused",
            "[1].rounds[1].attempted.broken.Forge.shell.[1]: shell exit 1: refused"
        ])
    }

    @Test("a timeout a catch takes fails its step with the trace")
    func aTimeoutFailsItsStepWithTheTrace() async throws {
        // Given
        let harness = Harness()
        let collected = Collected()
        let spec = try harness.frontend.workflow("""
        returns: "Dictionary<String, Any>"
        body:
          - var: slow
            type: String
            value: ""
          - let: attempted
            value:
              try:
                body:
                  - let: late
                    value: { call: { procedure: shell, arguments: { command: [ sleepy ], timeout: 0.05 } } }
                catch:
                  - set: slow
                    value: recovered
        result: { dictionary: [ [slow, { ref: slow }] ] }
        """)
        let sut = try harness.executor(
            shell: MockShell(recorder: harness.recorder, delaySeconds: 5)
        ) { event in
            await collected.append(event)
        }

        // When
        let fields = try ValueBridge.fields(try await sut.run(spec))

        // Then
        let failed = await collected.events.filter { event in event.kind == .stepFailed }

        #expect(fields["slow"] == .string("recovered"))
        #expect(failed.map(\.stepID) == ["late"])
        #expect(failed.map(\.errorMessage) == ["attempted.late.Forge.shell.[1]: step timed out after 0.05s"])
    }

    @Test("a verb called in another verb's arguments is const and computes, so the statement's one step is the outer call")
    func aNestedVerbCallIsNoStep() async throws {
        // Given. An operand is read rather than run, so only a const verb
        // stands in another's arguments, and a const verb does not act.
        let harness = Harness()
        let collected = Collected()
        let spec = try harness.frontend.workflow("""
        returns: "Dictionary<String, Any>"
        failing: [extract_refused]
        body:
          - let: said
            value:
              call:
                procedure: resource
                arguments:
                  content: a.txt
                  inputs:
                    call:
                      procedure: extract
                      arguments:
                        text: "name=forge"
                        outputs: { dictionary: [ [name, { dictionary: [ [regex, "name=(\\\\w+)"] ] }] ] }
        result: { dictionary: [ [said, { ref: said }] ] }
        """)
        let sut = try harness.executor(files: ["a.txt": "hello ${name}"]) { event in
            await collected.append(event)
        }

        // When
        let fields = try ValueBridge.fields(try await sut.run(spec))

        // Then
        let steps = await collected.events.map { event in
            "\(event.stepID ?? "?"):\(event.kind.rawValue):\(event.action ?? "")"
        }

        #expect(fields["said"] == .string("hello forge"))
        #expect(steps == [
            "said:step.started:Forge.resource",
            "said:step.completed:"
        ])
    }

    // MARK: - Public
    // MARK: - Private
}
