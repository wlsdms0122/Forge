//
//  ProviderConfigTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/30/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("ProviderConfig Tests")
struct ProviderConfigTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("a CLI kind without an executable runs the CLI from PATH")
    func cliKindDefaultsExecutable() throws {
        // When
        let sut = try ProviderConfig(name: "codex", kind: "codex-cli", settings: [:], apiKey: nil)

        // Then
        #expect(sut.backend == .codexCLI(executable: "codex"))
    }
    
    @Test("openai-compat carries its endpoint and the API key")
    func openAICompatibleCarriesEndpointAndKey() throws {
        // When
        let sut = try ProviderConfig(
            name: "local",
            kind: "openai-compat",
            settings: ["endpoint": "http://localhost:11434/v1"],
            apiKey: "secret"
        )

        // Then
        let endpoint = try #require(URL(string: "http://localhost:11434/v1"))
        #expect(sut.backend == .openAICompatible(endpoint: endpoint, apiKey: "secret"))
    }
    
    @Test(
        "a declaration forge cannot build is refused with what the kind needs",
        arguments: [
            (nil, [:], "'kind' is required, one of claude-cli, codex-cli, openai-compat"),
            ("made-up", [:], "kind 'made-up' is not one of claude-cli, codex-cli, openai-compat"),
            ("openai-compat", [:], "openai-compat requires 'endpoint', the base URL")
        ] as [(String?, [String: String], String)]
    )
    func undecodableDeclarationIsRefused(
        kind: String?,
        settings: [String: String],
        message: String
    ) {
        // When
        #expect {
            _ = try ProviderConfig(name: "x", kind: kind, settings: settings, apiKey: nil)
        } throws: { error in
            // Then
            (error as? ProviderDeclarationError)?.message == message
        }
    }
    
    // MARK: - Private
}
