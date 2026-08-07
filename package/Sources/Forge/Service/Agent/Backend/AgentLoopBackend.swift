//
//  AgentLoopBackend.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct AgentLoopBackend: Backend {
    struct ToolOutcome {
        // MARK: - Property
        let text: String
        let isError: Bool
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    let transport: any ChatTransport
    let translator: OpenAICompatibleTranslator
    
    // MARK: - Initializer
    init(
        transport: any ChatTransport,
        translator: OpenAICompatibleTranslator = OpenAICompatibleTranslator()
    ) {
        self.transport = transport
        self.translator = translator
    }
    
    // MARK: - Public
    static func execute(
        _ call: ChatToolCall,
        commandAuthorization: CommandAuthorizationPolicy,
        workingDirectory: String?,
        environment: [String: String]?
    ) async -> ToolOutcome {
        guard call.name == "run_command" else {
            return ToolOutcome(
                text: "unknown tool '\(call.name)'. only 'run_command' is available.",
                isError: true
            )
        }
        
        guard let argv = parseArgv(call.arguments) else {
            return ToolOutcome(
                text: "no non-empty 'argv' string array found in tool arguments:"
                    + " \(call.arguments)",
                isError: true
            )
        }
        
        switch commandAuthorization.authorize(argv: argv) {
        case .denied(let reason):
            return ToolOutcome(text: "command denied — \(reason)", isError: true)
        
        case .allowed(let argv):
            do {
                let toolEnvironment = SubprocessEnv.merge(
                    baseline: SubprocessEnv.baseline(),
                    specOverride: environment
                )
                let result = try await Subprocess.run(
                    executable: argv[0],
                    args: Array(argv.dropFirst()),
                    cwd: workingDirectory,
                    envExtra: toolEnvironment
                )
                
                if result.exitCode != 0 {
                    let combined = "exit \(result.exitCode)\n"
                        + result.stdout
                        + (result.stderr.isEmpty ? "" : "\n" + result.stderr)
                    
                    return ToolOutcome(text: combined, isError: true)
                }
                
                return ToolOutcome(text: result.stdout, isError: false)
            } catch {
                let message = (error as? ForgeError)?.message ?? "\(error)"
                
                return ToolOutcome(text: "command execution failed: \(message)", isError: true)
            }
        }
    }
    
    static func parseArgv(_ argumentsJSON: String) -> [String]? {
        guard
            let data = argumentsJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let argv = object["argv"] as? [String],
            !argv.isEmpty
        else {
            return nil
        }
        
        return argv
    }
    
    func openSession() -> any BackendSession {
        AgentLoopSession()
    }
    
    func invoke(_ invocation: Invocation) async throws -> BackendResponse {
        let translated = try translator.translate(invocation.agent)
        let native = translated.value
        
        await AgentEventLog.translation(
            invocationID: invocation.id,
            backend: "openai-compatible",
            diagnostics: translated.diagnostics
        )
        
        let model = native.model
        let modelReference = try invocation.agent.model.replacingModel(with: model)
        invocation.executionContext.record(modelReference: modelReference)
        
        let modelLabel = modelReference.displayName
        let commandAuthorization = native.commandAuthorization
        let jsonMode = false
        let tools = native.tools
        let workingDirectory = native.workingDirectory
        let environment = native.environment
        let session = (invocation.session as? AgentLoopSession) ?? AgentLoopSession()
        session.messages.append(ChatMessage(role: .user, content: invocation.prompt))
        
        var toolEvents: [ToolEvent] = []
        var totalUsage: AgentUsage?
        
        let started = ContinuousClock.now
        var iteration = 0
        
        while true {
            iteration += 1
            
            let roundNumber = iteration - 1
            
            try Task.checkCancellation()
            
            let roundStartedAt = Date()
            let roundStarted = ContinuousClock.now
            let completion = try await transport.complete(
                messages: session.messages,
                tools: tools,
                model: model,
                jsonMode: jsonMode
            )
            let roundUsage = completion.usage.map(AgentUsage.init(providerValues:))
            
            if let roundUsage {
                totalUsage = totalUsage?.adding(roundUsage) ?? roundUsage
            }
            
            func recordTurn() async {
                await AgentEventLog.turn(
                    invocationID: invocation.id,
                    model: modelLabel,
                    turn: roundNumber,
                    output: completion.text,
                    toolCalls: completion.toolCalls.count,
                    usage: roundUsage,
                    durationMilliseconds: (ContinuousClock.now - roundStarted).milliseconds,
                    startedAt: roundStartedAt
                )
            }
            
            guard completion.finishReason.completesTurn else {
                await recordTurn()
                
                throw IncompleteCompletion(
                    "agent turn did not complete (finish_reason:"
                        + " \(completion.finishReason.rawValue ?? "-")) — the answer is a"
                        + " fragment, not a result; for `length` raise the token budget or"
                        + " shorten the prompt"
                )
            }
            
            if completion.toolCalls.isEmpty {
                if iteration > 1 { await recordTurn() }
                
                session.messages.append(
                    ChatMessage(role: .assistant, content: completion.text)
                )
                
                return BackendResponse(
                    text: completion.text,
                    modelReference: modelReference,
                    usage: totalUsage,
                    toolEvents: toolEvents,
                    stdoutLength: completion.text.utf8.count,
                    durationMs: (ContinuousClock.now - started).milliseconds
                )
            }
            
            session.messages.append(
                ChatMessage(
                    role: .assistant,
                    content: completion.text,
                    toolCalls: completion.toolCalls
                )
            )
            
            for (sequence, call) in completion.toolCalls.enumerated() {
                let outcome = await Self.execute(
                    call,
                    commandAuthorization: commandAuthorization,
                    workingDirectory: workingDirectory,
                    environment: environment
                )
                
                await AgentEventLog.tool(
                    invocationID: invocation.id,
                    model: modelLabel,
                    turn: roundNumber,
                    sequence: sequence,
                    name: call.name,
                    input: call.arguments,
                    resultPreview: outcome.text,
                    isError: outcome.isError
                )
                
                session.messages.append(
                    ChatMessage(role: .tool, content: outcome.text, toolCallID: call.id)
                )
                
                toolEvents.append(
                    ToolEvent(
                        id: call.id,
                        name: call.name,
                        input: call.arguments,
                        resultPreview: String(outcome.text.prefix(300)),
                        isError: outcome.isError
                    )
                )
            }
            
            await recordTurn()
        }
    }
    
    // MARK: - Private
}
