//
//  CommandAuthorizationPolicyTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("CommandAuthorizationPolicy Tests")
struct CommandAuthorizationPolicyTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    // MARK: - tokenize
    @Test("splits a simple whitespace-separated command into tokens")
    func tokenizeSimple() throws {
        #expect(try CommandAuthorizationPolicy.tokenize("a b c") == ["a", "b", "c"])
    }
    
    @Test("collapses consecutive whitespace into one")
    func tokenizeCollapsesWhitespace() throws {
        #expect(try CommandAuthorizationPolicy.tokenize("  a\t  b  ") == ["a", "b"])
    }
    
    @Test("single-quoted content is one token, taken verbatim")
    func tokenizeSingleQuotePreservesContent() throws {
        #expect(try CommandAuthorizationPolicy.tokenize(#"q --input '{"text":"a b; c"}'"#) == ["q", "--input", #"{"text":"a b; c"}"#])
    }
    
    @Test("double quotes group by the same rule")
    func tokenizeDoubleQuote() throws {
        #expect(try CommandAuthorizationPolicy.tokenize(#"echo "hello world""#) == ["echo", "hello world"])
    }
    
    @Test("an escaped space does not split tokens")
    func tokenizeEscapedSpace() throws {
        #expect(try CommandAuthorizationPolicy.tokenize(#"a\ b"#) == ["a b"])
    }
    
    @Test("unbalanced quotes throw — no guessing and stitching")
    func tokenizeUnbalancedQuoteThrows() {
        #expect(throws: (any Error).self) { try CommandAuthorizationPolicy.tokenize("echo 'unterminated") }
    }
    
    @Test("a trailing backslash also throws")
    func tokenizeTrailingBackslashThrows() {
        #expect(throws: (any Error).self) { try CommandAuthorizationPolicy.tokenize(#"echo a\"#) }
    }
    
    // MARK: - match (token glob)
    @Test("only an exactly equal token sequence matches")
    func matchExact() throws {
        #expect(try commandPattern(["a", "b"]).matches(["a", "b"]))
        #expect(!(try commandPattern(["a", "b"]).matches(["a", "b", "c"])))
        #expect(!(try commandPattern(["a", "b"]).matches(["a"])))
    }
    
    @Test("a trailing * accepts all following arguments")
    func matchTrailingStar() throws {
        #expect(try commandPattern(["a", "*"]).matches(["a", "b", "c"]))
        #expect(try commandPattern(["a", "*"]).matches(["a"]))
    }
    
    // MARK: - CommandPattern shape invariants (enforced at construction)
    @Test("a pattern must start with an executable")
    func patternMustStartWithAnExecutable() {
        #expect(throws: (any Error).self) { try CommandPattern(tokens: ["*"]) }
        #expect(throws: (any Error).self) { try CommandPattern(tokens: []) }
        #expect(throws: (any Error).self) { try CommandPattern("*") }
    }
    
    @Test("a quoted * is rejected, not promoted to a wildcard")
    func quotedAsteriskIsRejectedNotPromotedToWildcard() {
        #expect(throws: (any Error).self) { try CommandPattern("grep '*'") }
        #expect(throws: (any Error).self) { try CommandPattern(#"grep "*""#) }
        #expect(throws: (any Error).self) { try CommandPattern(#"grep \*"#) }
        #expect(throws: Never.self) { try CommandPattern("grep *") }
    }
    
    @Test("empty tokens cannot enter a pattern")
    func emptyTokenIsRejected() {
        #expect(throws: (any Error).self) { try CommandPattern("''") }
        #expect(throws: (any Error).self) { try CommandPattern(tokens: [""]) }
        #expect(throws: (any Error).self) { try CommandPattern(tokens: ["grep", ""]) }
    }
    
    @Test("a wildcard may only appear in the last position")
    func patternWildcardOnlyFinal() {
        #expect(throws: (any Error).self) { try CommandPattern(tokens: ["git", "*", "push"]) }
        #expect(throws: Never.self) { try CommandPattern(tokens: ["git", "push", "*"]) }
    }
    
    @Test("pattern invariants hold through wire decoding")
    func patternInvariantSurvivesWireDecode() throws {
        // Given
        let data = Data(#"["*"]"#.utf8)

        // Then
        #expect(throws: (any Error).self) { try JSONDecoder().decode(CommandPattern.self, from: data) }
        let valid = try JSONDecoder().decode(CommandPattern.self, from: Data(#"["git","*"]"#.utf8))
        #expect(valid.matches(["git", "push"]))
    }
    
    @Test("an exact pattern does not implicitly allow trailing arguments")
    func exactPatternDoesNotImplicitlyAllowTrailingArguments() throws {
        // Given
        let policy = CommandAuthorizationPolicy(allowed: [try commandPattern(["git", "pull"])])
        guard case .allowed = policy.authorize(argv: ["git", "pull"]) else {

        // Then
            Issue.record("exact command should be allowed")
            
            return
        }
        
        guard case .denied = policy.authorize(argv: ["git", "pull", "origin", "main"]) else {
            Issue.record("trailing arguments require an explicit wildcard")
            
            return
        }
    }
    
    // MARK: - authorize
    @Test("commands matching a pattern are allowed through")
    func authorizeAllowsMatchingBrainCommand() throws {
        // Given
        let policy = CommandAuthorizationPolicy(allowed: [try commandPattern(["./brain/llmemory", "query", "--home", "brain", "*"])])
        guard case .allowed(let argv) =
        policy.authorize(argv: ["./brain/llmemory", "query", "--home", "brain", "search", "foo"])
        else {

        // Then
            Issue.record("expected: allowed")
            
            return
        }
        #expect(argv.first == "./brain/llmemory")
    }
    
    @Test("an executable at a different path with the same basename is not allowed")
    func authorizeDoesNotAllowDifferentExecutablePathByBasename() throws {
        // Given
        let policy = CommandAuthorizationPolicy(allowed: [try commandPattern(["git", "*"])])
        guard case .denied = policy.authorize(argv: ["/usr/bin/git", "diff"]) else {

        // Then
            Issue.record("an allow declaration must match the executable path exactly")
            
            return
        }
    }
    
    @Test("leading environment variable assignments are rejected")
    func authorizeRejectsLeadingEnvironmentAssignment() throws {
        // Given
        let policy = CommandAuthorizationPolicy(allowed: [try commandPattern(["git", "status"])])
        guard case .denied(let reason) =
        policy.authorize(argv: ["PATH=/tmp/tools", "git", "status"])
        else {

        // Then
            Issue.record("the policy must judge the same executable that will run")
            
            return
        }
        #expect(reason.contains("agent environment"), Comment(rawValue: reason))
    }
    
    @Test("leading assignments are rejected even when not the judged target")
    func leadingAssignmentIsRejectedEvenWithoutJudgement() {
        // Given
        let policy = CommandAuthorizationPolicy(allowed: nil)
        guard case .denied = policy.authorize(argv: ["PATH=/tmp", "git", "status"]) else {

        // Then
            Issue.record("assignment prefix splits judged and executed binaries")
            
            return
        }
    }
    
    @Test("judges the real executable behind a launcher")
    func authorizeJudgesTheDelegatedExecutableBehindLaunchers() throws {
        // Given
        let policy = CommandAuthorizationPolicy(allowed: [try commandPattern(["forge", "*"])])
        for arguments in [
            ["env", "--", "gh", "pr", "list"],
            ["command", "gh", "repo", "view"],
            ["exec", "--", "gh", "auth", "status"],
        ] {
            guard case .denied = policy.authorize(argv: arguments) else {

        // Then
                Issue.record("launcher must not hide an unlisted executable: \(arguments)")
                
                return
            }
        }
    }
    
    @Test("environment variable assignments behind a launcher are rejected the same way")
    func environmentAssignmentThroughLauncherIsRejectedLikeBareAssignment() throws {
        // Given
        let policy = CommandAuthorizationPolicy(allowed: [try commandPattern(["forge", "*"])])
        for arguments in [
            ["env", "FORGE_PROFILE=dev", "forge", "status"],
            ["/usr/bin/env", "PATH=/tmp/evil", "forge", "status"],
            ["env", "--", "A=1", "forge", "status"],
        ] {
            guard case .denied(let reason) = policy.authorize(argv: arguments) else {

        // Then
                Issue.record("assignments must not ride a launcher: \(arguments)")
                
                return
            }
            
            #expect(reason.contains("agent environment"), Comment(rawValue: reason))
        }
    }
    
    @Test("when the delegated command is allowed, the launcher form is preserved")
    func authorizePreservesLauncherShapeWhenDelegatedCommandIsAllowed() throws {
        // Given
        let policy = CommandAuthorizationPolicy(allowed: [try commandPattern(["forge", "*"])])
        let arguments = ["/usr/bin/env", "--", "forge", "status"]
        guard case .allowed(let authorizedArguments) = policy.authorize(argv: arguments) else {

        // Then
            Issue.record("launcher should use the delegated command's authorization")
            
            return
        }
        
        #expect(authorizedArguments == arguments, "execution must retain launcher shape")
    }
    
    @Test("launcher options with ambiguous interpretation are rejected")
    func authorizeRejectsAmbiguousLauncherOptions() throws {
        // Given
        let policy = CommandAuthorizationPolicy(allowed: [try commandPattern(["gh", "*"])])
        for arguments in [["env", "-S", "gh api user"], ["command", "-p", "gh"]] {
            guard case .denied = policy.authorize(argv: arguments) else {

        // Then
                Issue.record("launcher options must fail closed: \(arguments)")
                
                return
            }
        }
    }
    
    @Test("explicitly allowing the launcher itself takes precedence over normalization")
    func explicitAllowOfLauncherItselfWinsOverLauncherNormalization() throws {
        // Given
        let policy = CommandAuthorizationPolicy(allowed: [try commandPattern(["command", "-v", "*"])])
        guard case .allowed = policy.authorize(argv: ["command", "-v", "llmemory", "forge"]) else {

        // Then
            Issue.record("a declared launcher pattern must be honored")
            
            return
        }
        
        guard case .denied = policy.authorize(argv: ["command", "-p", "gh"]) else {
            Issue.record("undeclared launcher options still fail closed")
            
            return
        }
    }
    
    @Test("nil allowed means no judgment happens at all")
    func nilAllowedMeansNoJudgement() {
        // Given
        let policy = CommandAuthorizationPolicy(allowed: nil)
        guard case .allowed = policy.authorize(argv: ["anything", "goes"]) else {

        // Then
            Issue.record("nil allow-list is the bypass overlay")
            
            return
        }
        
        #expect(!policy.isEmpty)
    }
    
    @Test("executables not in the list are denied")
    func authorizeDeniesUnlistedExecutable() throws {
        // Given
        let policy = CommandAuthorizationPolicy(allowed: [try commandPattern(["./brain/llmemory", "query", "--home", "brain", "*"])])
        guard case .denied = policy.authorize(argv: ["rm", "-rf", "/tmp/x"]) else {

        // Then
            Issue.record("expected: denied")
            
            return
        }
    }
    
    @Test("denies when the leading arguments diverge")
    func authorizeDeniesArgPrefixMismatch() throws {
        // Given
        let policy = CommandAuthorizationPolicy(allowed: [try commandPattern(["python3", "./brain/llmemory", "query", "--home", "brain", "*"])])
        guard case .denied = policy.authorize(argv: ["python3", "-c", "import os"]) else {

        // Then
            Issue.record("expected: denied")
            
            return
        }
    }
    
    @Test("with no patterns at all, everything is denied")
    func authorizeDeniesWhenNoPatterns() {
        // Given
        let policy = CommandAuthorizationPolicy(allowed: [])
        guard case .denied = policy.authorize(argv: ["echo", "hi"]) else {

        // Then
            Issue.record("expected: denied")
            
            return
        }
    }
    
    @Test("chained commands are treated as literals, not interpreted as shell")
    func authorizeChainedCommandIsLiteralNotShell() throws {
        // Given
        let policy = CommandAuthorizationPolicy(allowed: [try commandPattern(["./brain/llmemory", "query", "--home", "brain", "*"])])
        guard case .allowed(let argv) =
        policy.authorize(argv: ["./brain/llmemory", "query", "--home", "brain", "x", ";", "rm", "-rf", "~"])
        else {

        // Then
            Issue.record("expected: allowed (only llmemory is executed)")
            
            return
        }
        #expect(argv.first == "./brain/llmemory")
        #expect(argv.contains(";"), "the semicolon must be a literal argument token")
    }
    
    // MARK: - isEmpty
    @Test("an empty command is judged as empty")
    func isEmpty() throws {
        #expect(CommandAuthorizationPolicy(allowed: []).isEmpty)
        #expect(!CommandAuthorizationPolicy(allowed: [try commandPattern(["echo"])]).isEmpty)
        #expect(!CommandAuthorizationPolicy(allowed: nil).isEmpty)
    }
    
    // MARK: - Private
}
