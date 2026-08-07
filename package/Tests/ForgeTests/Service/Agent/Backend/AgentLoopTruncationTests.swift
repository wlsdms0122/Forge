//
//  AgentLoopTruncationTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("AgentLoopTruncation Tests")
struct AgentLoopTruncationTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("a truncated final turn is failed, not passed off as success")
    func truncatedFinalTurnFailsLoud() async {
        // Given
        let transport = StubChatTransport([
                ChatCompletion(text: "cut off after saying only this much", finishReason: .length),
        ])
        let backend = AgentLoopBackend(transport: transport)
        do {

        // When
            let response = try await backend.invoke(invocation())

        // Then
            Issue.record("a truncated turn was promoted to the final answer: '\(response.text)'")
        } catch is IncompleteCompletion {
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
    
    @Test("a content-filter cutoff is also surfaced as failure")
    func contentFilterTerminationFailsLoud() async {
        // Given
        let transport = StubChatTransport([
                ChatCompletion(text: "partial", finishReason: .contentFilter),
        ])
        let backend = AgentLoopBackend(transport: transport)
        do {

        // When
            _ = try await backend.invoke(invocation())

        // Then
            Issue.record("a turn cut off by content_filter succeeded")
        } catch is IncompleteCompletion {
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
    
    @Test("truncated tool calls are not executed")
    func truncatedToolCallTurnIsNotExecuted() async {
        // Given
        let transport = StubChatTransport([
                ChatCompletion(
                    text: "",
                    toolCalls: [ChatToolCall(id: "c1", name: "run_command",
                            arguments: #"{"argv":["/bin/echo","half"#)],
                    finishReason: .length),
                ChatCompletion(text: "must never reach this round"),
        ])
        let backend = AgentLoopBackend(transport: transport)
        do {

        // When
            _ = try await backend.invoke(invocation())

        // Then
            Issue.record("a truncated tool_calls turn was executed")
        } catch is IncompleteCompletion {
            let calls = await transport.callCount
            #expect(calls == 1, "the loop continued past the truncated turn")
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
    
    @Test("unknown finish reasons are not promoted to success")
    func unknownFinishReasonIsNotPromotedToSuccess() async {
        let transport = StubChatTransport([ChatCompletion(text: "fragment", finishReason: .other("abort"))])
        let backend = AgentLoopBackend(transport: transport)
        do {
            _ = try await backend.invoke(invocation())
            Issue.record("an unknown finish_reason was promoted to success")
        } catch is IncompleteCompletion {
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
    
    @Test("stop and unspecified count as normal completion")
    func stopAndUnspecifiedStillSucceed() async throws {
        for reason in [ChatFinishReason.stop, .unspecified] {
            let transport = StubChatTransport([ChatCompletion(text: "ok", finishReason: reason)])
            let backend = AgentLoopBackend(transport: transport)
            let response = try await backend.invoke(invocation())
            #expect(response.text == "ok", "\(reason)")
        }
    }
    
    // MARK: - Finish state types
    @Test("finish reasons round-trip the provider string verbatim")
    func finishReasonRoundTripsProviderStrings() {
        #expect(ChatFinishReason(rawValue: "length") == .length)
        #expect(ChatFinishReason(rawValue: "content_filter") == .contentFilter)
        #expect(ChatFinishReason(rawValue: "tool_calls") == .toolCalls)
        #expect(ChatFinishReason(rawValue: nil) == .unspecified)
        #expect(ChatFinishReason(rawValue: "eos") == .other("eos"))
        #expect(ChatFinishReason(rawValue: "eos").rawValue == "eos")
        #expect(ChatFinishReason.unspecified.rawValue == nil)
    }
    
    @Test("completion reasons are a closed allowlist")
    func completionIsAClosedAllowlist() {
        #expect(ChatFinishReason.stop.completesTurn)
        #expect(ChatFinishReason.toolCalls.completesTurn)
        #expect(ChatFinishReason.unspecified.completesTurn)
        #expect(!ChatFinishReason.length.completesTurn)
        #expect(!ChatFinishReason.contentFilter.completesTurn)
        #expect(!ChatFinishReason.other("abort").completesTurn)
    }
    
    @Test("maps wire length to truncation")
    func parseMapsLengthFromWire() throws {
        let json = Data(#"{"choices":[{"finish_reason":"length","message":{"content":"cut"}}]}"#.utf8)
        let parsed = try OpenAICompatibleBackend.parse(json)
        #expect(parsed.finishReason == .length)
    }
    
    // MARK: - Private
    private func agent(_ allowed: [AgentTool] = []) -> Agent {
        try! Agent(model: "local:m", allowed: allowed)
    }
    
    private func invocation() -> Invocation {
        Invocation(id: "t", agent: agent(), prompt: "go")
    }
}
