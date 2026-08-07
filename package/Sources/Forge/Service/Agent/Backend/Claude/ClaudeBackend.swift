//
//  ClaudeBackend.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct ClaudeBackend: Backend {
    // MARK: - Property
    let executable: String
    let translator: ClaudeTranslator
    
    // MARK: - Initializer
    init(executable: String = "claude", translator: ClaudeTranslator = ClaudeTranslator()) {
        self.executable = executable
        self.translator = translator
    }
    
    // MARK: - Public
    static func validateSuccessfulProtocol(_ parsed: StreamParseResult, turn: Int? = nil) throws {
        let location = turn.map { turn in " (turn \(turn))" } ?? ""
        
        guard parsed.malformedLineCount == 0 else {
            throw BackendProtocolViolation(
                "claude emitted \(parsed.malformedLineCount) malformed stream"
                    + " frame(s)\(location)"
            )
        }
        
        guard parsed.sawTerminalResult else {
            throw BackendProtocolViolation(
                "claude successful turn omitted its terminal result envelope\(location)"
            )
        }
        
        guard !parsed.finalText.isEmpty || !parsed.toolEvents.isEmpty else {
            throw BackendProtocolViolation(
                "claude successful turn observed neither text nor a tool call\(location)"
            )
        }
    }
    
    static func failureDetail(stderr: String, stdout: String) -> String {
        let error = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !error.isEmpty { return String(error.prefix(300)) }
        
        let detail = ResponseExtract.text(Diagnostics.lastLine(stdout))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return String(detail.prefix(300))
    }
    
    static func buildArgs(
        configuration: ClaudeAgentConfiguration,
        user: String,
        outputFormat: String,
        session: [String] = [],
        extra: [String]
    ) -> [String] {
        var arguments: [String] = ["--print", "-p", user]
        
        if let model = configuration.model { arguments += ["--model", model] }
        
        arguments += session
        
        if let mode = configuration.permissionMode {
            arguments += ["--permission-mode", mode]
        }
        
        arguments += ["--output-format", outputFormat]
        
        if let tools = configuration.availableTools {
            arguments += ["--tools", tools.joined(separator: ",")]
        }
        
        if let allowed = configuration.allowedTools {
            arguments += ["--allowedTools", allowed.joined(separator: " ")]
        }
        
        arguments += extra
        
        return arguments
    }
    
    func invoke(_ invocation: Invocation) async throws -> BackendResponse {
        let translated = try translator.translate(invocation.agent)
        let native = translated.value
        
        await AgentEventLog.translation(
            invocationID: invocation.id,
            backend: "claude",
            diagnostics: translated.diagnostics
        )
        
        let modelReference = try invocation.agent.model.replacingModel(with: native.model)
        invocation.executionContext.record(modelReference: modelReference)
        
        let outputFormat = "stream-json"
        let extraArgs: [String] = ["--verbose"]
        let claudeSession = invocation.session as? ClaudeSession
        let sessionID = claudeSession?.sessionID ?? UUID().uuidString
        let baseIndex = claudeSession?.turnIndex ?? 0
        let established = claudeSession?.established ?? false
        let started = ContinuousClock.now
        
        try Task.checkCancellation()
        
        let index = baseIndex
        let sessionArgs: [String] = established
            ? ["--resume", sessionID]
            : ["--session-id", sessionID]
        let arguments = Self.buildArgs(
            configuration: native,
            user: invocation.prompt,
            outputFormat: outputFormat,
            session: sessionArgs,
            extra: extraArgs
        )
        let reader = StreamJSON.Reader()
        let lineHandler: Subprocess.StdoutLineHandler = { (frame: Data, at: Date) in
            reader.feed(frame: frame, at: at)
        }
        let result = try await Subprocess.run(
            executable: executable,
            args: arguments,
            cwd: native.workingDirectory,
            envExtra: native.environment,
            stdin: "",
            onStdoutLine: lineHandler
        )
        
        claudeSession?.established = true
        
        try Task.checkCancellation()
        
        if result.exitCode != 0 {
            throw BackendNonzeroExit(
                "claude exit \(result.exitCode) (turn \(index)):"
                    + " \(Self.failureDetail(stderr: result.stderr, stdout: result.stdout))",
                exitCode: result.exitCode,
                stderr: result.stderr,
                stdout: result.stdout
            )
        }
        
        let parsed = reader.snapshot()
        let toolEvents = parsed.toolEvents
        
        for (sequence, event) in toolEvents.enumerated() {
            await AgentEventLog.tool(
                invocationID: invocation.id,
                model: modelReference.displayName,
                turn: index,
                sequence: sequence,
                name: event.name,
                input: event.input,
                resultPreview: event.resultPreview,
                isError: event.isError,
                durationMilliseconds: event.durationMs,
                startedAt: event.startedAt,
                completedAt: event.completedAt
            )
        }
        
        try Self.validateSuccessfulProtocol(parsed, turn: index)
        
        let text = parsed.finalText
        let usage = parsed.usage.map { usage in
            AgentUsage(providerValues: usage.asDictionary)
        }
        claudeSession?.turnIndex = baseIndex + 1
        
        let durationMs = (ContinuousClock.now - started).milliseconds
        
        return BackendResponse(
            text: text,
            modelReference: modelReference,
            usage: (usage?.isEmpty ?? true) ? nil : usage,
            toolEvents: toolEvents,
            stdoutLength: result.stdout.count,
            durationMs: durationMs
        )
    }
    
    func openSession() -> any BackendSession {
        ClaudeSession(sessionID: UUID().uuidString)
    }
    
    // MARK: - Private
}

extension Duration {
    var milliseconds: Int {
        let components = components
        
        return Int(
            components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
        )
    }
}
