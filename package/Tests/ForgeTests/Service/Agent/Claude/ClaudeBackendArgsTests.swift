//
//  ClaudeBackendArgsTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("ClaudeBackendArgs Tests")
struct ClaudeBackendArgsTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("the first turn opens the session with session-id")
    func turn0UsesSessionId() {
        // Given
        let args = ClaudeBackend.buildArgs(
            configuration: configuration(), user: "boot up",
            outputFormat: "json",
            session: ["--session-id", "UUID-1"], extra: [])

        // Then
        #expect(adjacent(args, "--session-id", "UUID-1"))
        #expect(!args.contains("--resume"))
    }
    
    @Test("subsequent turns attach with resume")
    func resumeTurnUsesResume() {
        // Given
        let args = ClaudeBackend.buildArgs(
            configuration: configuration(), user: "do work",
            outputFormat: "json",
            session: ["--resume", "UUID-1"], extra: [])

        // Then
        #expect(adjacent(args, "--resume", "UUID-1"))
        #expect(!args.contains("--session-id"))
    }
    
    @Test("resume turns still pass all remaining flags through")
    func resumeTurnStillPassesAllFlags() {
        // Given
        let args = ClaudeBackend.buildArgs(
            configuration: configuration(permissionMode: .safe), user: "do work",
            outputFormat: "json",
            session: ["--resume", "UUID-1"], extra: ["--verbose"])

        // Then
        #expect(adjacent(args, "--model", "sonnet"), "model must be re-passed")
        #expect(adjacent(args, "--permission-mode", "dontAsk"), "permission-mode must be re-passed")
        #expect(adjacent(args, "--allowedTools", "Bash(forge) Bash(forge *)"), "tools must be re-passed")
        #expect(adjacent(args, "--tools", "Bash"), "available tools must be re-passed")
        #expect(args.contains("--verbose"))
    }
    
    @Test("with no permission mode specified, the flag is omitted entirely")
    func unspecifiedPermissionModeOmitsFlag() {
        // Given
        let args = ClaudeBackend.buildArgs(
            configuration: configuration(), user: "do work",
            outputFormat: "json",
            session: ["--resume", "UUID-1"], extra: [])

        // Then
        #expect(!args.contains("--permission-mode"), "unspecified permission mode must omit the flag entirely")
    }
    
    @Test("output format flags are always attached — parsing depends on them")
    func outputFormatAlwaysPresent() {
        // Given
        let args = ClaudeBackend.buildArgs(
            configuration: configuration(), user: "hi",
            outputFormat: "json",
            session: [], extra: [])

        // Then
        #expect(adjacent(args, "--output-format", "json"))
    }
    
    @Test("permission mode maps to the claude CLI vocabulary")
    func permissionModeMapsToClaudeCLIValues() {
        #expect(ClaudeTranslator.permissionMode(.bypass) == "bypassPermissions")
        #expect(ClaudeTranslator.permissionMode(.safe) == "dontAsk")
        #expect(ClaudeTranslator.permissionMode(.restrict) == "default")
    }
    
    @Test("an empty tool declaration turns native tools off")
    func explicitEmptyCapabilitiesDisableNativeTools() throws {
        // Given
        let agent = try Agent(
            model: "claude",
            allowed: [])
        let native = try ClaudeTranslator().translate(agent).value
        let args = ClaudeBackend.buildArgs(
            configuration: native, user: "hi", outputFormat: "json", session: [], extra: [])

        // Then
        #expect(adjacent(args, "--tools", ""))
        #expect(adjacent(args, "--allowedTools", ""))
    }
    
    @Test("with tools unspecified, no tool flags are attached")
    func unspecifiedToolsOmitToolFlags() throws {
        // Given
        let agent = try Agent(model: "claude")
        let native = try ClaudeTranslator().translate(agent).value
        let args = ClaudeBackend.buildArgs(
            configuration: native, user: "hi", outputFormat: "json", session: [], extra: [])

        // Then
        #expect(!args.contains("--tools"))
        #expect(!args.contains("--allowedTools"))
    }
    
    @Test("forge adds no extra tool gate on top of the backend")
    func forgeInstallsNoToolGateOverTheBackend() throws {
        // Given
        for allowed in [[], [AgentTool.filesRead]] {
            let agent = try Agent(model: "claude", allowed: allowed)
            let native = try ClaudeTranslator().translate(agent).value
            let args = ClaudeBackend.buildArgs(
                configuration: native, user: "hi", outputFormat: "json", session: [], extra: [])

        // Then
            #expect(!args.contains("--settings"), "forge must not inject a tool gate")
            #expect(!args.contains("--disallowedTools"), "deny axis no longer exists")
        }
    }
    
    @Test("no session means no session flags")
    func noSessionWhenEmpty() {
        // Given
        let args = ClaudeBackend.buildArgs(
            configuration: configuration(), user: "hi",
            outputFormat: "json", session: [], extra: [])

        // Then
        #expect(!args.contains("--session-id"))
        #expect(!args.contains("--resume"))
    }
    
    @Test("the same session keeps the same UUID across turns")
    func sameSessionUUIDAcrossTurns() {
        // Given
        let uuid = "SESSION-XYZ"
        let firstTurn = ClaudeBackend.buildArgs(
            configuration: configuration(), user: "a",
            outputFormat: "json", session: ["--session-id", uuid], extra: [])
        let secondTurn = ClaudeBackend.buildArgs(
            configuration: configuration(), user: "b",
            outputFormat: "json", session: ["--resume", uuid], extra: [])

        // Then
        #expect(adjacent(firstTurn, "--session-id", uuid))
        #expect(adjacent(secondTurn, "--resume", uuid))
    }
    
    // MARK: - Private
    private func configuration(permissionMode: PermissionMode? = nil) -> ClaudeAgentConfiguration {
        let agent = try! Agent(
            model: "claude:sonnet",
            allowed: [.command(try commandPattern(["forge", "*"]))],
            permissionMode: permissionMode
        )
        
        return try! ClaudeTranslator().translate(agent).value
    }
    
    private func adjacent(_ args: [String], _ flag: String, _ value: String) -> Bool {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return false }
        
        return args[index + 1] == value
    }
}
