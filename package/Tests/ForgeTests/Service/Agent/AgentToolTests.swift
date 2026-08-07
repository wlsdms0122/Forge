//
//  AgentToolTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import Forge

@Suite("AgentTool Tests")
struct AgentToolTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("tool declarations decode into a provider-neutral form")
    func decodesProviderNeutralToolShapes() throws {
        #expect(try AgentToolReference.decode(.string("files.read")) == .filesRead)
        #expect(try AgentToolReference.decode(.object([
                        "command": .string("forge workflow *")
            ])) == .command(try commandPattern(["forge", "workflow", "*"])))
        #expect(try AgentToolReference.decode(.object(["mcp": .string("github.*")])) == .modelContextProtocol("github.*"))
    }
    
    @Test("quoted arguments are preserved through tokenization")
    func commandPatternTokenizationPreservesQuotedArguments() throws {
        #expect(try AgentToolReference.decode(.object([
                        "command": .string(#"git pull "feature branch""#)
            ])) == .command(try commandPattern(["git", "pull", "feature branch"])))
    }
    
    @Test("unknown tools fail instead of being silently ignored")
    func unknownToolFailsLoud() {
        #expect(throws: (any Error).self) { try AgentToolReference.decode(.string("Bash")) }
        #expect(throws: (any Error).self) {
            try AgentToolReference.decode(.object(["command": .string("")]))
        }
        #expect(throws: (any Error).self) {
            try AgentToolReference.decode(.object([
                        "command": .string("forge * workflow")
            ]))
        }
        #expect(throws: (any Error).self) {
            try AgentToolReference.decode(.object([
                        "command": .array([.string("forge"), .string("*")])
            ]))
        }
        #expect(throws: (any Error).self) {
            try AgentToolReference.decode(.object(["claude_tool": .string("Read")]))
        }
    }
    
    @Test("omitted allowed and an empty array mean different things")
    func allowedOmissionAndExplicitEmptyRemainDifferent() throws {
        #expect(try Agent(model: "claude").allowed == nil)
        #expect(try Agent(model: "claude", allowed: []).allowed == [])
    }
    
    @Test("provider vocabulary is owned by the claude translator — it does not leak into core")
    func claudeTranslatorOwnsProviderVocabulary() throws {
        // Given
        let agent = try Agent(
            model: "claude",
            allowed: [.filesRead, .command(try commandPattern(["forge", "workflow", "*"]))])

        // When
        let translated = try ClaudeTranslator().translate(agent).value

        // Then
        #expect(translated.model == nil)
        #expect(translated.allowedTools == [
                "Read", "Glob", "Grep",
                "Bash(forge workflow)", "Bash(forge workflow *)",
        ])
        #expect(translated.availableTools == ["Read", "Glob", "Grep", "Bash"])
        #expect(translated.permissionMode == nil)
    }
    
    @Test("empty allowed translates to a no-tools request")
    func emptyAllowedTranslatesToAnEmptyToolRequest() throws {
        // Given
        let agent = try Agent(model: "claude", allowed: [])
        let translated = try ClaudeTranslator().translate(agent).value

        // Then
        #expect(translated.availableTools == [])
        #expect(translated.allowedTools == [])
    }
    
    @Test("allowed and permission mode are carried independently")
    func claudeCarriesAllowedAndPermissionModeIndependently() throws {
        // Given
        let agent = try Agent(
            model: "claude", allowed: [.filesRead], permissionMode: .bypass)

        // When
        let translated = try ClaudeTranslator().translate(agent).value

        // Then
        #expect(translated.availableTools == ["Read", "Glob", "Grep"])
        #expect(translated.permissionMode == "bypassPermissions")
    }
    
    @Test("declaring bypass together with allowed is rejected")
    func openAIRejectsBypassDeclaredWithAllowed() {
        #expect(throws: ProtocolError.self) {
            let agent = try Agent(
                model: "local:m", allowed: [.filesRead], permissionMode: .bypass)
            _ = try OpenAICompatibleTranslator().translate(agent)
        }
    }
    
    @Test("unspecified allowed closes to nothing, not allow-all")
    func openAIUnspecifiedAllowedCollapsesToNothingNotEverything() throws {
        // Given
        let omitted = try Agent(model: "local:m")
        let translated = try OpenAICompatibleTranslator().translate(omitted).value

        // Then
        #expect(translated.tools.isEmpty)
        #expect(translated.commandAuthorization.authorize(argv: ["anything"]) ==
            .denied(reason: "no command tool declaration matched"))
        let bypass = try Agent(model: "local:m", permissionMode: .bypass)
        let unrestricted = try OpenAICompatibleTranslator().translate(bypass).value
        #expect(unrestricted.commandAuthorization.authorize(argv: ["anything"]) ==
            .allowed(argv: ["anything"]))
    }
    
    @Test("function tool vocabulary is owned by the openai translator")
    func openAITranslatorOwnsFunctionToolVocabulary() throws {
        // Given
        let agent = try Agent(
            model: "local:model",
            allowed: [.command(try commandPattern(["forge", "*"]))])

        // When
        let translated = try OpenAICompatibleTranslator().translate(agent).value

        // Then
        #expect(translated.tools.map(\.name) == ["run_command"])
        #expect(translated.tools[0].parametersJSON.contains("\"argv\""))
    }
    
    @Test("restrict without an approval channel closes the tool surface")
    func openAIRestrictWithoutApprovalChannelClosesTheToolSurface() throws {
        // Given
        let agent = try Agent(
            model: "local:model",
            allowed: [.command(try commandPattern(["forge", "*"]))],
            permissionMode: .restrict)

        // When
        let translated = try OpenAICompatibleTranslator().translate(agent)

        // Then
        #expect(translated.value.tools.isEmpty)
        #expect(translated.diagnostics.contains { diagnostic in
                diagnostic.field == "permission" && diagnostic.message.contains("tool-less")
        })
    }
    
    @Test("the translator preserves command patterns verbatim")
    func translatorsPreserveExactCommandPattern() throws {
        // Given
        let agent = try Agent(
            model: "local:model",
            allowed: [.command(try commandPattern(["git", "pull"]))])

        // When
        let openAI = try OpenAICompatibleTranslator().translate(agent).value

        // Then
        #expect(openAI.commandAuthorization.authorize(argv: ["git", "pull"]) == .allowed(argv: ["git", "pull"]))
        #expect(openAI.commandAuthorization.authorize(argv: ["git", "pull", "origin"]) ==
            .denied(reason: "no command tool declaration matched"))
        let claudeAgent = try Agent(
            model: "claude",
            allowed: [.command(try commandPattern(["git", "pull"]))])
        let claude = try ClaudeTranslator().translate(claudeAgent).value
        #expect(claude.allowedTools == ["Bash(git pull)"])
    }
    
    // MARK: - Private
}
