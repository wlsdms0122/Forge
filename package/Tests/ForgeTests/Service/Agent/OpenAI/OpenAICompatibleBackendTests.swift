//
//  OpenAICompatibleBackendTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("OpenAICompatibleBackend Tests", .exclusive(.stubURLProtocol))
struct OpenAICompatibleBackendTests {
    // MARK: - Property
    private static let userMsg = [ChatMessage(role: .user, content: "hi")]
    
    // MARK: - Initializer
    // MARK: - Test
    // MARK: - parse (pure)
    @Test("extracts body text and usage from the response")
    func parseExtractsContentAndUsage() throws {
        // Given
        let json = #"""
        {"choices":[{"message":{"role":"assistant","content":"Pong"}}],
         "usage":{"prompt_tokens":15,"completion_tokens":3,"total_tokens":18}}
        """#.data(using: .utf8)!

        // When
        let parsed = try OpenAICompatibleBackend.parse(json)

        // Then
        #expect(parsed.text == "Pong")
        #expect(parsed.usage?["total_tokens"] == 18)
        #expect(parsed.usage?["prompt_tokens"] == 15)
    }
    
    @Test("throws malformed when the body is missing")
    func parseMissingContentThrowsMalformed() throws {
        // Given
        let json = #"{"choices":[{"message":{"role":"assistant"}}]}"#.data(using: .utf8)!

        // Then
        let error = try #require(throws: (any Error).self) { try OpenAICompatibleBackend.parse(json) }
        
        #expect(error is MalformedOutput, "expected MalformedOutput, got \(error)")
    }
    
    @Test("throws malformed when it is not JSON")
    func parseNonJSONThrowsMalformed() throws {
        // Given
        let data = "not json at all".data(using: .utf8)!

        // Then
        let error = try #require(throws: (any Error).self) { try OpenAICompatibleBackend.parse(data) }
        
        #expect(error is MalformedOutput, "expected MalformedOutput, got \(error)")
    }
    
    @Test("extracts tool calls even when the body is null")
    func parseExtractsToolCallsWithNullContent() throws {
        // Given
        let json = #"""
        {"choices":[{"finish_reason":"tool_calls","message":{"role":"assistant","content":null,
         "tool_calls":[{"id":"c1","type":"function",
           "function":{"name":"bash","arguments":"{\"command\":\"ls\"}"}}]}}]}
        """#.data(using: .utf8)!

        // When
        let parsed = try OpenAICompatibleBackend.parse(json)

        // Then
        #expect(parsed.text == "")
        #expect(parsed.finishReason == .toolCalls)
        #expect(parsed.toolCalls.count == 1)
        #expect(parsed.toolCalls.first?.name == "bash")
        #expect(parsed.toolCalls.first?.arguments == #"{"command":"ls"}"#)
    }
    
    @Test("reads tool call arguments as an object")
    func parseToolCallArgumentsAsObject() throws {
        // Given
        let json = #"""
        {"choices":[{"message":{"role":"assistant","content":null,
         "tool_calls":[{"id":"c2","type":"function",
           "function":{"name":"bash","arguments":{"command":"echo hi"}}}]}}]}
        """#.data(using: .utf8)!

        // When
        let parsed = try OpenAICompatibleBackend.parse(json)

        // Then
        #expect(parsed.toolCalls.count == 1)
        let args = parsed.toolCalls.first?.arguments ?? ""
        #expect(args.contains("\"command\""), Comment(rawValue: args))
        #expect(args.contains("echo hi"), Comment(rawValue: args))
    }
    
    @Test("one broken tool call rejects the whole response — no partial acceptance")
    func parseRejectsWholeResponseWhenAnyToolCallMalformed() throws {
        // Given
        let json = #"""
        {"choices":[{"message":{"role":"assistant","content":null,
         "tool_calls":[
           {"id":"c1","type":"function","function":{"name":"bash","arguments":"{}"}},
           {"id":"c2","type":"function","function":{"arguments":"{}"}}]}}]}
        """#.data(using: .utf8)!

        // Then
        let error = try #require(throws: (any Error).self) { try OpenAICompatibleBackend.parse(json) }
        
        #expect(error is MalformedOutput, "expected MalformedOutput, got \(error)")
    }
    
    @Test("rejects when tool_calls is not an array")
    func parseRejectsNonArrayToolCalls() throws {
        // Given
        let json = #"""
        {"choices":[{"message":{"role":"assistant","content":"hi","tool_calls":{"bad":true}}}]}
        """#.data(using: .utf8)!

        // Then
        let error = try #require(throws: (any Error).self) { try OpenAICompatibleBackend.parse(json) }
        
        #expect(error is MalformedOutput, "expected MalformedOutput, got \(error)")
    }
    
    // MARK: - error translation
    @Test("transport timeouts translate to backend timeouts")
    func translateTimeoutIsBackendTimeout() {
        // Given
        let translated = OpenAICompatibleBackend.translate(URLError(.timedOut))

        // Then
        #expect(translated is BackendTimeout, "got \(type(of: translated))")
        #expect(translated.wireType == "BackendTimeout")
    }
    
    @Test("connection refused translates to unavailable")
    func translateConnectionRefusedIsUnavailable() {
        // Given
        let translated = OpenAICompatibleBackend.translate(URLError(.cannotConnectToHost))

        // Then
        #expect(translated is BackendUnavailable, "got \(type(of: translated))")
        #expect(translated.wireType == "BackendUnavailable")
    }
    
    @Test("classifies HTTP status codes into failure kinds")
    func hTTPErrorClassification() {
        // Given
        let unavailable = OpenAICompatibleBackend.httpError(status: 503, body: Data())

        // Then
        #expect(unavailable is BackendUnavailable, "5xx → Unavailable, got \(type(of: unavailable))")
        let nonzeroExit = OpenAICompatibleBackend.httpError(status: 404, body: Data())
        #expect(nonzeroExit is BackendNonzeroExit, "4xx → NonzeroExit, got \(type(of: nonzeroExit))")
    }
    
    // MARK: - requestBody
    @Test("JSON mode request body shape")
    func requestBodyJSONMode() {
        // Given
        let body = OpenAICompatibleBackend.requestBody(
            model: "m",
            messages: [ChatMessage(role: .system, content: "sys"),
                ChatMessage(role: .user, content: "u")],
            tools: [],
            jsonMode: true)

        // Then
        #expect(body["response_format"] != nil)
        #expect(body["temperature"] as? Int == 0)
        #expect(body["stream"] as? Bool == false)
        let messages = body["messages"] as? [[String: Any]]
        #expect(messages?.count == 2)
        #expect(messages?.first?["role"] as? String == "system")
        #expect(messages?.last?["role"] as? String == "user")
    }
    
    @Test("with no tools, the tools key is omitted entirely")
    func requestBodyOmitsEmptyTools() {
        // Given
        let body = OpenAICompatibleBackend.requestBody(
            model: "m",
            messages: [ChatMessage(role: .user, content: "u")],
            tools: [],
            jsonMode: false)

        // Then
        #expect(body["response_format"] == nil)
        #expect(body["tools"] == nil)
        let messages = body["messages"] as? [[String: Any]]
        #expect(messages?.count == 1)
        #expect(messages?.first?["role"] as? String == "user")
    }
    
    @Test("with no model specified, the model key is omitted")
    func requestBodyOmitsUnspecifiedModel() {
        // Given
        let body = OpenAICompatibleBackend.requestBody(
            model: nil,
            messages: [ChatMessage(role: .user, content: "u")],
            tools: [],
            jsonMode: false)

        // Then
        #expect(body["model"] == nil)
    }
    
    @Test("tools and tool calls are carried in the request body")
    func requestBodyIncludesToolsAndToolCalls() {
        // Given
        let tool = ToolSpec(name: "bash", description: "run",
            parametersJSON: #"{"type":"object"}"#)
        let body = OpenAICompatibleBackend.requestBody(
            model: "m",
            messages: [
                ChatMessage(role: .assistant, content: "",
                    toolCalls: [ChatToolCall(id: "c1", name: "bash",
                            arguments: #"{"command":"ls"}"#)]),
                ChatMessage(role: .tool, content: "out", toolCallID: "c1"),
            ],
            tools: [tool],
            jsonMode: false)
        let tools = body["tools"] as? [[String: Any]]

        // Then
        #expect(tools?.count == 1)
        #expect((tools?.first?["function"] as? [String: Any])?["name"] as? String == "bash")
        let messages = body["messages"] as? [[String: Any]]
        let asst = messages?.first
        #expect(asst?["tool_calls"] != nil)
        #expect(messages?.last?["tool_call_id"] as? String == "c1")
    }
    
    @Test("a normal response comes back as a completion")
    func completeReturnsCompletion() async throws {
        // Given
        StubURLProtocol.handler = { request in
            let body = #"{"choices":[{"message":{"content":"ok"}}],"usage":{"total_tokens":5}}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!
            
            return (response, body.data(using: .utf8)!)
        }
        
        let completion = try await stubTransport().complete(
            messages: Self.userMsg, tools: [], model: "llama3.1:8b",
            jsonMode: false)

        // Then
        #expect(completion.text == "ok")
        #expect(completion.usage?["total_tokens"] == 5)
        #expect(completion.toolCalls.isEmpty)
    }
    
    @Test("500 throws as unavailable")
    func completeHTTP500ThrowsUnavailable() async {
        // Given
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503,
                httpVersion: nil, headerFields: nil)!
            
            return (response, Data("overloaded".utf8))
        }
        do {
            _ = try await stubTransport().complete(
                messages: Self.userMsg, tools: [], model: "m",
                jsonMode: false)

        // Then
            Issue.record("expected throw")
        } catch let translated as BackendUnavailable {
            #expect(translated.message.contains("503"), Comment(rawValue: translated.message))
        } catch {
            Issue.record("expected BackendUnavailable, got \(error)")
        }
    }
    
    @Test("404 throws as abnormal exit")
    func completeHTTP404ThrowsNonzeroExit() async {
        // Given
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404,
                httpVersion: nil, headerFields: nil)!
            
            return (response, Data("model not found".utf8))
        }
        do {
            _ = try await stubTransport().complete(
                messages: Self.userMsg, tools: [], model: "m",
                jsonMode: false)

        // Then
            Issue.record("expected throw")
        } catch is BackendNonzeroExit {
        } catch {
            Issue.record("expected BackendNonzeroExit, got \(error)")
        }
    }
    
    // MARK: - live integration (real Ollama)
    @Test(
        "request and response round-trip against a real Ollama",
        .enabled(
            if: ProcessInfo.processInfo.environment["FORGE_LIVE_OLLAMA"] == "1",
            "live test — runs only when FORGE_LIVE_OLLAMA=1 (requires Ollama + llama3.1:8b)"
        )
    )
    func liveOllamaRoundtrip() async throws {
        // Given
        let transport = OpenAICompatibleBackend(
            baseURL: URL(string: "http://localhost:11434/v1")!
        )
        let completion = try await transport.complete(
            messages: [
                ChatMessage(role: .system, content: "You are a test endpoint. Reply tersely."),
                ChatMessage(role: .user, content: "Reply with exactly one word: pong"),
            ],
            tools: [], model: "llama3.1:8b", jsonMode: false)

        // Then
        #expect(!completion.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "response text is empty")
        print("── live ollama text: \(completion.text)")
        print("── live ollama usage: \(completion.usage ?? [:])")
    }
    
    // MARK: - Private
    // MARK: - complete (URLProtocol stub)
    private func stubTransport() -> OpenAICompatibleBackend {
        OpenAICompatibleBackend(
            baseURL: URL(string: "http://localhost:11434/v1")!,
            session: StubURLProtocol.session())
    }
}
