//
//  ClaudeToolMappingInvariantTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import Forge

@Suite("ClaudeToolMappingInvariant Tests")
struct ClaudeToolMappingInvariantTests {
    // MARK: - Property
    private let nonCommandTools: [AgentTool] = [
        .filesRead, .filesWrite, .web, .delegate, .schedule, .modelContextProtocol("*"),
    ]
    
    // MARK: - Initializer
    // MARK: - Test
    @Test("both surfaces map identically for every category except command")
    func bothSurfacesAgreeOnEveryNonCommandCategory() {
        // Given
        for tool in nonCommandTools {

        // Then
            #expect(ClaudeTranslator.tools([tool]) == ClaudeTranslator.availableTools([tool]), "the two surfaces disagree on \(tool) — the mapping has drifted apart again")
        }
    }
    
    @Test("command is the only point of divergence")
    func commandIsTheOnlyDivergence() throws {
        // Given
        let tool = AgentTool.command(try CommandPattern(tokens: ["git", "status"]))

        // Then
        #expect(ClaudeTranslator.availableTools([tool]) == ["Bash"])
        #expect(ClaudeTranslator.tools([tool]) == ["Bash(git status)"])
    }
    
    @Test("the command wildcard leaves both native patterns")
    func commandWildcardKeepsBothNativePatterns() throws {
        // Given
        let tool = AgentTool.command(try CommandPattern(tokens: ["git", "*"]))

        // Then
        #expect(ClaudeTranslator.tools([tool]) == ["Bash(git)", "Bash(git *)"])
        #expect(ClaudeTranslator.availableTools([tool]) == ["Bash"])
    }
    
    @Test("the available tool list is deduplicated")
    func availableToolsDeduplicates() throws {
        // Given
        let tools: [AgentTool] = [
            .command(try CommandPattern(tokens: ["git"])),
            .command(try CommandPattern(tokens: ["ls"])),
            .filesRead, .filesRead,
        ]

        // Then
        #expect(ClaudeTranslator.availableTools(tools) == ["Bash", "Read", "Glob", "Grep"])
    }
    
    @Test("with no categories, no tools are mapped")
    func noCategoryMapsToNothing() {
        // Given
        for tool in nonCommandTools {

        // Then
            #expect(!ClaudeTranslator.tools([tool]).isEmpty, "\(tool) exposes no native name")
            #expect(!ClaudeTranslator.availableTools([tool]).isEmpty, "\(tool) exposes no native name")
        }
    }
    
    @Test("MCP patterns project into a fixed shape")
    func mCPPatternProjection() {
        #expect(ClaudeTranslator.availableTools([.modelContextProtocol("*")]) == ["mcp__*"])
        #expect(ClaudeTranslator.availableTools([.modelContextProtocol("notion.search")]) == ["mcp__notion__search"])
    }
    
    // MARK: - Private
}
