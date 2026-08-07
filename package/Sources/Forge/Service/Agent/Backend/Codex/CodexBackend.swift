//
//  CodexBackend.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct CodexBackend: Backend {
    // MARK: - Property
    let executable: String
    let translator: CodexTranslator
    
    // MARK: - Initializer
    init(executable: String = "codex", translator: CodexTranslator = CodexTranslator()) {
        self.executable = executable
        self.translator = translator
    }
    
    // MARK: - Public
    static func validateSuccessfulProtocol(_ result: CodexEventStreamResult) throws {
        guard result.malformedLineCount == 0 else {
            throw BackendProtocolViolation(
                "codex emitted \(result.malformedLineCount) malformed JSONL event(s)"
            )
        }
        
        guard result.sawThreadStarted, result.threadIdentifier?.isEmpty == false else {
            throw BackendProtocolViolation(
                "codex successful turn omitted thread.started with a thread_id"
            )
        }
        
        guard result.sawAgentMessage else {
            throw BackendProtocolViolation(
                "codex successful turn omitted a completed agent_message"
            )
        }
        
        guard result.sawTurnCompleted else {
            throw BackendProtocolViolation("codex successful turn omitted turn.completed")
        }
    }
    
    static func arguments(agentArguments: [String], resume threadIdentifier: String?) -> [String] {
        var arguments = ["exec"]
        
        if threadIdentifier != nil { arguments.append("resume") }
        
        arguments += ["--json", "--skip-git-repo-check"]
        arguments += agentArguments
        
        if let threadIdentifier { arguments.append(threadIdentifier) }
        
        arguments.append("-")
        
        return arguments
    }
    
    static func failureDetail(stderr: String, stdout: String) -> String {
        let error = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !error.isEmpty { return String(error.prefix(300)) }
        
        return String(Diagnostics.lastLine(stdout).prefix(300))
    }
    
    func openSession() -> any BackendSession { CodexSession() }
    
    func invoke(_ invocation: Invocation) async throws -> BackendResponse {
        let translated = try translator.translate(invocation.agent)
        let native = translated.value
        
        await AgentEventLog.translation(
            invocationID: invocation.id,
            backend: "codex",
            diagnostics: translated.diagnostics
        )
        
        let session = invocation.session as? CodexSession
        let baseIndex = session?.turnIndex ?? 0
        let agentArguments = translator.agentArguments(configuration: native)
        let arguments = Self.arguments(
            agentArguments: agentArguments,
            resume: session?.threadIdentifier
        )
        let modelReference = try invocation.agent.model.replacingModel(with: native.model)
        invocation.executionContext.record(modelReference: modelReference)
        
        let modelLabel = modelReference.displayName
        let eventLogContext = AgentEventLogContext.current
        let reader = CodexEventStream.Reader()
        let started = ContinuousClock.now
        
        try Task.checkCancellation()
        
        let result: SubprocessResult
        
        do {
            result = try await Subprocess.run(
                executable: executable,
                args: arguments,
                cwd: native.workingDirectory,
                envExtra: native.environment,
                stdin: invocation.prompt,
                onStdoutLine: { frame, at in reader.feed(frame: frame, at: at) }
            )
        } catch {
            _ = await Self.logTools(
                reader.snapshot().toolEvents,
                invocation: invocation,
                model: modelLabel,
                turn: baseIndex,
                context: eventLogContext
            )
            
            throw error
        }
        
        let streamed = reader.snapshot()
        
        if let threadIdentifier = streamed.threadIdentifier {
            session?.threadIdentifier = threadIdentifier
        }
        
        let parsed = streamed
        let observedToolEvents = await Self.logTools(
            parsed.toolEvents,
            invocation: invocation,
            model: modelLabel,
            turn: baseIndex,
            context: eventLogContext
        )
        
        try Task.checkCancellation()
        
        if result.exitCode != 0 {
            let detail = parsed.failure
                ?? Self.failureDetail(stderr: result.stderr, stdout: result.stdout)
            
            throw BackendNonzeroExit(
                "codex exit \(result.exitCode) (turn \(baseIndex)): \(detail)",
                exitCode: result.exitCode,
                stderr: result.stderr,
                stdout: result.stdout
            )
        }
        
        try Self.validateSuccessfulProtocol(parsed)
        
        session?.turnIndex = baseIndex + 1
        
        let turnUsage = parsed.usage.map { total -> AgentUsage in
            let baseline = session?.cumulativeUsage
            session?.cumulativeUsage = total
            
            return baseline.map { baseline in total.subtracting(baseline) } ?? total
        }
        
        return BackendResponse(
            text: parsed.finalText,
            modelReference: modelReference,
            usage: turnUsage,
            toolEvents: observedToolEvents,
            stdoutLength: result.stdout.count,
            durationMs: (ContinuousClock.now - started).milliseconds
        )
    }
    
    // MARK: - Private
    private static func logTools(
        _ completed: [ToolEvent],
        invocation: Invocation,
        model: String,
        turn: Int,
        context: AgentEventLogContext
    ) async -> [ToolEvent] {
        let observed = completed
            .enumerated()
            .sorted { left, right in
                let leftDate = left.element.startedAt ?? left.element.completedAt
                let rightDate = right.element.startedAt ?? right.element.completedAt
                
                switch (leftDate, rightDate) {
                case let (leftDate?, rightDate?) where leftDate != rightDate:
                    return leftDate < rightDate
                
                default:
                    return left.offset < right.offset
                }
            }
            .map(\.element)
        
        for (sequence, event) in observed.enumerated() {
            await AgentEventLog.tool(
                invocationID: invocation.id,
                model: model,
                turn: turn,
                sequence: sequence,
                name: event.name,
                input: event.input,
                resultPreview: event.resultPreview,
                isError: event.isError,
                durationMilliseconds: event.durationMs,
                startedAt: event.startedAt,
                completedAt: event.completedAt,
                context: context
            )
        }
        
        return observed
    }
}
