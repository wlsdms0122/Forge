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
        func invoke(_ invocation: Invocation) async throws -> BackendResponse {
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
        let executor = Executor(backends: registry)

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
        let executor = Executor(backends: registry)
        do {

        // When
            _ = try await executor.run(makeInv(provider: "unregistered"))

        // Then
            Issue.record("expected ResolutionError")
        } catch let error as ResolutionError {
            #expect(error.message.contains("unregistered"), "error message must name the missing provider — got: \(error.message)")
            #expect(error.message.contains("claude"), "error message must list registered providers — got: \(error.message)")
        } catch {
            Issue.record("expected ResolutionError, got \(error)")
        }
    }
    
    // MARK: - Private
    private func makeInv(provider: String) -> Invocation {
        Invocation(
            id: "i",
            agent: try! Agent(model: "\(provider):x"),
            prompt: "hi"
        )
    }
}
