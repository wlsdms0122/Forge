//
//  AgentModelParsingTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import Forge

@Suite("AgentModelParsing Tests")
struct AgentModelParsingTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("provider:model form reads as that specific model")
    func specificModel() throws {
        // Given
        let model = try ModelReference("claude:sonnet")

        // Then
        #expect(model.provider == "claude")
        #expect(model.model == "sonnet")
        #expect(!model.isBackendDefault)
    }
    
    @Test("provider alone uses the backend default model")
    func providerOnlyUsesBackendDefault() throws {
        // Given
        let model = try ModelReference("claude")

        // Then
        #expect(model.provider == "claude")
        #expect(model.model == "")
        #expect(model.isBackendDefault)
    }
    
    @Test("a colon inside the model name is not a separator")
    func modelPortionMayContainColons() throws {
        // Given
        let model = try ModelReference("local:llama3.1:8b")

        // Then
        #expect(model.provider == "local")
        #expect(model.model == "llama3.1:8b")
    }
    
    @Test("throws when provider is missing or nothing follows the colon")
    func missingProviderOrEmptyModelAfterColonThrows() {
        #expect(throws: (any Error).self) { try ModelReference("") }
        #expect(throws: (any Error).self) { try ModelReference(":sonnet") }
        #expect(throws: (any Error).self) { try ModelReference("claude:") }
        #expect(throws: (any Error).self) { try ModelReference("claude:auto") }
    }
    
    @Test("rejects an invalid model reference at Agent creation time")
    func agentInitRejectsMalformedModel() {
        #expect(throws: (any Error).self) { try Agent(model: "") }
    }
    
    @Test("a structured reference uses the provider/model fields as-is")
    func structuredReferenceUsesProviderAndModelFields() throws {
        // Given
        let reference = try ModelReference(provider: "codex", model: "gpt-5.4")

        // Then
        #expect(reference.provider == "codex")
        #expect(reference.model == "gpt-5.4")
    }
    
    // MARK: - Private
}
