//
//  CodexTranslatorTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("CodexTranslator Tests")
struct CodexTranslatorTests {
    // MARK: - Property
    private let translator = CodexTranslator()
    
    // MARK: - Initializer
    // MARK: - Test
    @Test("with permission unspecified, codex's own settings are untouched")
    func nilPermissionPreservesNativeConfiguration() throws {
        // Given
        let agent = try Agent(model: "codex", workingDirectory: "/work")
        let native = try translator.translate(agent).value

        // Then
        #expect(native.model == nil)
        #expect(native.workingDirectory == "/work")
        #expect(!native.permissionArguments.contains(where: { permissionArgument in permissionArgument.contains("sandbox_mode") }))
        #expect(!native.permissionArguments.contains("--dangerously-bypass-approvals-and-sandbox"))
    }
    
    @Test("safe permission and tools map to the codex vocabulary")
    func safePermissionAndToolsMapToCodexTerms() throws {
        // Given
        let agent = try Agent(
            model: "codex:gpt-x",
            allowed: [.filesRead, .command(try commandPattern(["forge", "*"]))],
            permissionMode: .safe)

        // When
        let native = try translator.translate(agent).value

        // Then
        #expect(native.model == "gpt-x")
        #expect(native.permissionArguments.contains("sandbox_mode=\"workspace-write\""))
        #expect(native.permissionArguments.contains("approval_policy=\"never\""))
        #expect(native.configurationArguments.contains("web_search=\"disabled\""))
        #expect(native.configurationArguments.contains(
        "shell_environment_policy.ignore_default_excludes=true"))
        #expect(adjacent(native.configurationArguments, "--disable", "multi_agent"))
    }
    
    @Test("bypass goes through the codex native flag")
    func bypassMapsToCodexNativeFlag() throws {
        // Given
        let agent = try Agent(model: "codex", permissionMode: .bypass)
        let native = try translator.translate(agent).value

        // Then
        #expect(native.permissionArguments.contains("--dangerously-bypass-approvals-and-sandbox"))
    }
    
    @Test("no forge tool gate is carried in the arguments")
    func agentArgumentsCarryNoForgeToolGate() throws {
        // Given
        let agent = try Agent(
            model: "codex",
            allowed: [.filesRead, .command(try commandPattern(["forge", "*"]))])
        let arguments = translator.agentArguments(
            configuration: try translator.translate(agent).value)

        // Then
        #expect(!arguments.contains("--enable"))
        #expect(!arguments.contains("--dangerously-bypass-hook-trust"))
        #expect(!arguments.contains(where: { argument in argument.hasPrefix("hooks.") }))
        #expect(!arguments.contains(where: { argument in argument.contains("_codex-authorize-tool") }))
    }
    
    @Test("both initial and resume arguments use codex native forms")
    func initialAndResumeArgumentsUseNativeCodexShape() throws {
        // Given
        let native = try translator.translate(Agent(model: "codex:gpt-x")).value
        let initial = CodexBackend.arguments(
            agentArguments: translator.agentArguments(configuration: native),
            resume: nil)

        // Then
        #expect(initial.prefix(2) == ["exec", "--json"])
        #expect(!initial.contains("resume"))
        #expect(adjacent(initial, "--model", "gpt-x"))
        #expect(initial.last == "-")
        let resumed = CodexBackend.arguments(
            agentArguments: translator.agentArguments(configuration: native),
            resume: "thread-1")
        #expect(resumed.prefix(3) == ["exec", "resume", "--json"])
        #expect(Array(resumed.suffix(2)) == ["thread-1", "-"])
    }
    
    @Test("restrict without an approval channel closes the tool surface")
    func restrictWithoutApprovalChannelClosesTheToolSurface() throws {
        // Given
        let agent = try Agent(
            model: "codex",
            allowed: [.command(try commandPattern(["forge", "*"])), .web, .delegate],
            permissionMode: .restrict)

        // When
        let translated = try translator.translate(agent)

        // Then
        #expect(translated.value.permissionArguments.contains("sandbox_mode=\"read-only\""))
        #expect(translated.value.configurationArguments.contains("web_search=\"disabled\""))
        #expect(adjacent(translated.value.configurationArguments, "--disable", "multi_agent"))
        #expect(translated.diagnostics.contains { diagnostic in
                diagnostic.field == "permission" && diagnostic.message.contains("tool-less")
        })
    }
    
    // MARK: - Private
    private func adjacent(_ arguments: [String], _ flag: String, _ value: String) -> Bool {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return false }
        
        return arguments[index + 1] == value
    }
}
