//
//  AgentLoopBackendTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge


private actor FailOnceChatTransport: ChatTransport {
    private var failed = false
    private(set) var lastMessages: [ChatMessage] = []
    func complete(
        messages: [ChatMessage], tools: [ToolSpec], model: String?, jsonMode: Bool
    ) async throws -> ChatCompletion {
        lastMessages = messages
        if !failed {
            failed = true
            throw BackendUnavailable("transient")
        }
        
        return ChatCompletion(text: "recovered")
    }
}

private actor FailAfterToolRoundTransport: ChatTransport {
    private var call = 0
    private let first: ChatCompletion
    private(set) var lastMessages: [ChatMessage] = []
    init(first: ChatCompletion) { self.first = first }
    func complete(
        messages: [ChatMessage], tools: [ToolSpec], model: String?, jsonMode: Bool
    ) async throws -> ChatCompletion {
        call += 1
        lastMessages = messages
        switch call {
        case 1: return first
        case 2: throw BackendUnavailable("mid-loop transient")
        default: return ChatCompletion(text: "recovered")
        }
    }
}

@Suite("AgentLoopBackend Tests")
struct AgentLoopBackendTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("with no tools, completes in a single round trip")
    func singleShotWhenNoTools() async throws {
        // Given
        let transport = StubChatTransport([ChatCompletion(text: "hello")])
        let backend = AgentLoopBackend(transport: transport)

        // When
        let result = try await backend.invoke(invocation(profile([])))
        let callCount = await transport.callCount

        // Then
        #expect(result.text == "hello")
        #expect(callCount == 1)
        #expect(result.toolEvents.isEmpty)
    }
    
    @Test("the session accumulates consecutive user turns")
    func sessionAccumulatesConsecutiveUserTurns() async throws {
        // Given
        let transport = StubChatTransport([
                ChatCompletion(text: "boot-ack"),
                ChatCompletion(text: "ok"),
        ])
        let backend = AgentLoopBackend(transport: transport)
        let agent = profile([])
        let session = backend.openSession()

        // When
        _ = try await backend.invoke(Invocation(id: "t0", agent: agent, prompt: "turn-zero", session: session))
        _ = try await backend.invoke(Invocation(id: "t1", agent: agent, prompt: "turn-one", session: session))
        let users = await transport.lastMessages.filter { message in message.role == .user }.map { message in message.content }

        // Then
        #expect(users == ["turn-zero", "turn-one"], "the session accumulates consecutive agent turns as user messages")
    }
    
    @Test("a sent user message stays in the session even when the turn fails")
    func failedTurnStillWritesUserMessageBackToSession() async throws {
        // Given
        let transport = FailOnceChatTransport()
        let backend = AgentLoopBackend(transport: transport)
        let agent = profile([])
        let session = backend.openSession()
        do {
            _ = try await backend.invoke(
                Invocation(id: "failed", agent: agent, prompt: "first", session: session))

        // Then
            Issue.record("first transport call must fail")
        } catch is BackendUnavailable {}
        _ = try await backend.invoke(
            Invocation(id: "retry", agent: agent, prompt: "second", session: session))
        let users = await transport.lastMessages
        .filter { message in message.role == .user }.map { message in message.content }
        #expect(users == ["first", "second"])
    }
    
    @Test("records of already-executed tools survive even when the send after tool execution fails")
    func transportFailureAfterToolRoundKeepsExecutedToolsInSession() async throws {
        // Given
        let transport = FailAfterToolRoundTransport(
            first: commandCall("echo kept-evidence"))
        let backend = AgentLoopBackend(transport: transport)
        let agent = profile([.command(try commandPattern(["echo", "*"]))])
        let session = backend.openSession()
        do {
            _ = try await backend.invoke(
                Invocation(id: "die-mid", agent: agent, prompt: "first", session: session))

        // Then
            Issue.record("the second transport call should fail")
        } catch is BackendUnavailable {}
        _ = try? await backend.invoke(
            Invocation(id: "retry", agent: agent, prompt: "second", session: session))
        let seen = await transport.lastMessages
        #expect(seen.contains { message in message.role == .tool && message.content.contains("kept-evidence") }, "if executed tool results vanish from the session, the next turn's model is unaware of its own bash side effects")
        #expect(seen.contains { message in message.role == .assistant && !(message.toolCalls ?? []).isEmpty }, "the assistant tool_calls turn must be preserved too")
    }
    
    @Test("runs the tool and produces the final answer from its result")
    func runsToolThenReturnsFinal() async throws {
        // Given
        let transport = StubChatTransport([
                commandCall("echo loop-marker-xyz"),
                ChatCompletion(text: "done"),
        ])
        let backend = AgentLoopBackend(transport: transport)

        // When
        let result = try await backend.invoke(invocation(profile([.command(try commandPattern(["echo", "*"]))])))
        let callCount = await transport.callCount
        let lastMessages = await transport.lastMessages

        // Then
        #expect(result.text == "done")
        #expect(callCount == 2)
        #expect(result.toolEvents.count == 1)
        #expect(result.toolEvents.first?.name == "run_command")
        #expect(!(result.toolEvents.first?.isError ?? true))
        #expect(result.toolEvents.first?.resultPreview.contains("loop-marker-xyz") ?? false, "tool stdout must be carried in the event")
        let toolMsg = lastMessages.first { lastMessage in lastMessage.role == .tool }
        #expect(toolMsg != nil)
        #expect(toolMsg?.content.contains("loop-marker-xyz") ?? false)
    }
    
    @Test("restrict mode picks the conservative fallback")
    func restrictPermissionModeUsesConservativeFallback() async throws {
        // Given
        let transport = StubChatTransport([ChatCompletion(text: "ok")])
        let backend = AgentLoopBackend(transport: transport)
        let agent = try Agent(
            model: "local:m",
            allowed: [],
            permissionMode: .restrict)

        // When
        let response = try await backend.invoke(invocation(agent))

        // Then
        #expect(response.text == "ok")
        let callCount = await transport.callCount
        #expect(callCount == 1)
    }
    
    @Test("bypass mode skips the allowlist judgment")
    func bypassPermissionModeSkipsAllowList() async throws {
        // Given
        let transport = StubChatTransport([
                commandCall("echo bypass-marker-abc"),
                ChatCompletion(text: "done"),
        ])
        let backend = AgentLoopBackend(transport: transport)
        let agent = try Agent(
            model: "local:m",
            permissionMode: .bypass)

        // When
        let result = try await backend.invoke(invocation(agent))

        // Then
        #expect(result.text == "done")
        #expect(result.toolEvents.count == 1)
        #expect(!(result.toolEvents.first?.isError ?? true))
        #expect(result.toolEvents.first?.resultPreview.contains("bypass-marker-abc") ?? false)
    }
    
    @Test("a provider-only model fails before transport")
    func providerOnlyModelFailsBeforeTransport() async throws {
        // Given
        let transport = StubChatTransport([ChatCompletion(text: "ok")])
        let backend = AgentLoopBackend(transport: transport)
        let agent = try Agent(model: "local", allowed: [])
        do {

        // When
            _ = try await backend.invoke(invocation(agent))

        // Then
            Issue.record("provider-only OpenAI-compatible model must fail")
        } catch is ProtocolError {}
        let callCount = await transport.callCount
        #expect(callCount == 0)
    }
    
    @Test("denied commands are fed back to the model as errors")
    func deniedCommandFedBackAsError() async throws {
        // Given
        let transport = StubChatTransport([
                commandCall("rm -rf /tmp/should-not-run"),
                ChatCompletion(text: "ok"),
        ])
        let backend = AgentLoopBackend(transport: transport)

        // When
        let result = try await backend.invoke(invocation(profile([.command(try commandPattern(["echo", "*"]))])))

        // Then
        #expect(result.text == "ok")
        #expect(result.toolEvents.count == 1)
        #expect(result.toolEvents.first?.isError ?? false)
        #expect(result.toolEvents.first?.resultPreview.contains("denied") ?? false)
    }
    
    @Test("unknown tool calls are also fed back as errors")
    func unknownToolFedBackAsError() async throws {
        // Given
        let transport = StubChatTransport([
                ChatCompletion(
                    text: "",
                    toolCalls: [ChatToolCall(id: "c1", name: "python",
                            arguments: "{}")],
                    finishReason: .toolCalls),
                ChatCompletion(text: "ok"),
        ])
        let backend = AgentLoopBackend(transport: transport)

        // When
        let result = try await backend.invoke(invocation(profile([.command(try commandPattern(["echo", "*"]))])))

        // Then
        #expect(result.text == "ok")
        #expect(result.toolEvents.first?.isError ?? false)
    }
    
    @Test(
        "the tool loop runs to completion against a real Ollama",
        .enabled(
            if: ProcessInfo.processInfo.environment["FORGE_LIVE_OLLAMA"] == "1",
            "live test — runs only when FORGE_LIVE_OLLAMA=1 (requires Ollama)"
        )
    )
    func liveOllamaAgentLoop() async throws {
        let transport = OpenAICompatibleBackend(
            baseURL: URL(string: "http://localhost:11434/v1")!)
        let backend = AgentLoopBackend(transport: transport)
        let agent = try Agent(
            model: "local:llama3.1:8b",
            allowed: [.command(try commandPattern(["echo", "*"]))])
        let invocation = Invocation(
            id: "live", agent: agent,
            prompt: "You run executables via the run_command tool. "
            + "Its only argument is a JSON string array field named 'argv'.\n\n"
            + "Use run_command with argv [\"echo\",\"loop-marker-live\"].")
        do {
            let result = try await backend.invoke(invocation)
            print("── agent loop final text: \(result.text)")
            for event in result.toolEvents {
                print("── tool: name=\(event.name ?? "?") isError=\(event.isError) "
                    + "input=\(event.input ?? "") result=\(event.resultPreview.prefix(120))")
            }
        } catch {
            print("── agent loop threw (cap or transport error): \(error)")
        }
    }
    
    @Test("stops the loop when a response without tools arrives")
    func loopTerminatesOnFirstNoToolResponse() async throws {
        // Given
        let transport = StubChatTransport([
                commandCall("echo x", id: "c1"),
                commandCall("echo y", id: "c2"),
                commandCall("echo z", id: "c3"),
                ChatCompletion(text: "final"),
        ])
        let backend = AgentLoopBackend(transport: transport)

        // When
        let result = try await backend.invoke(invocation(profile([.command(try commandPattern(["echo", "*"]))])))
        let callCount = await transport.callCount

        // Then
        #expect(result.text == "final")
        #expect(callCount == 4)
        #expect(result.toolEvents.count == 3)
    }
    
    // MARK: - Private
    private func profile(_ allowed: [AgentTool]) -> Agent {
        try! Agent(model: "local:m", allowed: allowed)
    }
    
    private func invocation(_ p: Agent) -> Invocation {
        Invocation(id: "t", agent: p, prompt: "go")
    }
    
    private func commandCall(_ command: String, id: String = "c1") -> ChatCompletion {
        let argv = (try? CommandAuthorizationPolicy.tokenize(command)) ?? []
        let data = try! JSONSerialization.data(withJSONObject: ["argv": argv])
        return ChatCompletion(
            text: "",
            toolCalls: [ChatToolCall(
                    id: id,
                    name: "run_command",
                    arguments: String(data: data, encoding: .utf8)!)],
            finishReason: .toolCalls)
    }
}
