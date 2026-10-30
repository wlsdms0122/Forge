//
//  BackendRegistryTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import Forge

@Suite("BackendRegistry Tests")
struct BackendRegistryTests {
    private struct TaggedBackend: Backend {
        let tag: String
        func invoke(_ invocation: AgentInvocation) async throws -> BackendResponse {
            BackendResponse(text: "from:\(tag)", usage: nil, toolEvents: [], stdoutLength: 0, durationMs: 1)
        }
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("finds a backend by provider name")
    func resolvesByProvider() async throws {
        // Given
        let registry = BackendRegistry([
                "claude": TaggedBackend(tag: "claude"),
                "codex":  TaggedBackend(tag: "codex"),
        ])
        let executor = AgentExecutor(backends: registry)

        // When
        let rClaude = try await executor.run(makeInv(provider: "claude"))

        // Then
        #expect(rClaude.text == "from:claude")
        let rCodex = try await executor.run(makeInv(provider: "codex"))
        #expect(rCodex.text == "from:codex")
    }
    
    @Test("unknown providers throw")
    func unknownProviderThrows() async {
        // Given
        let registry = BackendRegistry(["claude": TaggedBackend(tag: "claude")])
        let executor = AgentExecutor(backends: registry)
        do {

        // When
            _ = try await executor.run(makeInv(provider: "unregistered"))

        // Then
            Issue.record("expected BackendNotRegistered")
        } catch let error as BackendNotRegistered {
            #expect(error.message.contains("unregistered"), "error message must name the missing provider — got: \(error.message)")
            #expect(error.message.contains("claude"), "error message must list registered providers — got: \(error.message)")
        } catch {
            Issue.record("expected BackendNotRegistered, got \(error)")
        }
    }
    
    @Test("a model that names no provider resolves to the sole backend")
    func noProviderResolvesSoleBackend() async throws {
        // Given
        let sut = BackendRegistry(["claude": TaggedBackend(tag: "claude")])

        // When
        let backend = try sut.resolve(provider: nil)

        // Then
        let response = try await backend.invoke(makeInv(provider: "claude"))

        #expect(response.text == "from:claude")
    }
    
    @Test("a model that names no provider among several backends is refused in the model's words")
    func noProviderAmongSeveralIsRefused() throws {
        // Given
        let sut = BackendRegistry([
            "claude": TaggedBackend(tag: "claude"),
            "codex": TaggedBackend(tag: "codex")
        ])

        // When
        let error = try #require(throws: BackendNotRegistered.self) {
            try sut.resolve(provider: nil)
        }

        // Then
        #expect(
            error.message
                == "a model names no provider, and 2 backends are registered (claude, codex);"
                + " name one as `<provider>[:<model>]`"
        )
    }
    
    // MARK: - Private
    private func makeInv(provider: String) -> AgentInvocation {
        AgentInvocation(
            id: "i",
            agent: try! Agent(model: "\(provider):x"),
            prompt: "hi"
        )
    }
}
