//
//  BackendFactoryTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("BackendFactory Tests")
struct BackendFactoryTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("the claude-cli kind builds a claude backend")
    func claudeCliKindMakesClaudeBackend() {
        // Given
        let backend = BackendFactory.make(ProviderConfig(
                name: "claude", kind: "claude-cli", settings: ["executable": "claude"]))

        // Then
        #expect(backend is ClaudeBackend, "got \(String(describing: backend))")
    }
    
    @Test("the openai-compat kind builds an agent loop backend")
    func openAICompatibleKindMakesAgentLoopBackend() {
        // Given
        let backend = BackendFactory.make(ProviderConfig(
                name: "local", kind: "openai-compat",
                settings: ["endpoint": "http://localhost:11434/v1"]))

        // Then
        #expect(backend is AgentLoopBackend, "got \(String(describing: backend))")
    }
    
    @Test("the codex-cli kind builds a codex backend")
    func codexCliKindMakesCodexBackend() {
        // Given
        let backend = BackendFactory.make(ProviderConfig(
                name: "codex", kind: "codex-cli", settings: ["executable": "codex"]))

        // Then
        #expect(backend is CodexBackend, "got \(String(describing: backend))")
    }
    
    @Test("the openai-compatible backend wraps the matching transport")
    func openAICompatibleBackendWrapsOpenAICompatibleTransport() {
        // Given
        let backend = BackendFactory.make(ProviderConfig(
                name: "local", kind: "openai-compat",
                settings: ["endpoint": "http://localhost:11434/v1"]))
        let loop = backend as? AgentLoopBackend

        // Then
        #expect(loop != nil)
        #expect(loop?.transport is OpenAICompatibleTransport, "got \(String(describing: loop?.transport))")
    }
    
    @Test("unknown kinds build nothing — nil")
    func unknownKindIsNil() {
        // Given
        let backend = BackendFactory.make(ProviderConfig(
                name: "x", kind: "made-up-kind", settings: [:]))

        // Then
        #expect(backend == nil)
    }
    
    @Test("without an endpoint, nothing is built")
    func openAICompatibleMissingEndpointIsNil() {
        // Given
        let backend = BackendFactory.make(ProviderConfig(
                name: "local", kind: "openai-compat", settings: [:]))

        // Then
        #expect(backend == nil)
    }
    
    // MARK: - Private
}
