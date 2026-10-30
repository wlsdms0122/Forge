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
    func claudeCLIKindMakesClaudeBackend() {
        // When
        let sut = BackendFactory.make(.claudeCLI(executable: "claude"))

        // Then
        #expect(sut is ClaudeBackend, "got \(sut)")
    }
    
    @Test("the openai-compat kind builds an agent loop backend")
    func openAICompatibleKindMakesAgentLoopBackend() {
        // When
        let sut = BackendFactory.make(
            .openAICompatible(endpoint: URL(string: "http://localhost:11434/v1")!, apiKey: nil)
        )

        // Then
        #expect(sut is AgentLoopBackend, "got \(sut)")
    }
    
    @Test("the codex-cli kind builds a codex backend")
    func codexCLIKindMakesCodexBackend() {
        // When
        let sut = BackendFactory.make(.codexCLI(executable: "codex"))

        // Then
        #expect(sut is CodexBackend, "got \(sut)")
    }
    
    @Test("the openai-compatible backend wraps the matching transport")
    func openAICompatibleBackendWrapsOpenAICompatibleTransport() {
        // When
        let sut = BackendFactory.make(
            .openAICompatible(endpoint: URL(string: "http://localhost:11434/v1")!, apiKey: nil)
        )

        // Then
        let loop = sut as? AgentLoopBackend
        #expect(loop?.transport is OpenAICompatibleTransport, "got \(String(describing: loop?.transport))")
    }
    
    // MARK: - Private
}
