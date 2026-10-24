//
//  PolicyStoreTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("PolicyStore Tests")
struct PolicyStoreTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("policy")

    // MARK: - Initializer
    // MARK: - Test
    @Test("principal matches by exact match and wildcard")
    func principalExactAndWildcard() {
        #expect(Principal.matches(pattern: "cli:response", principal: "cli:response"))
        #expect(Principal.matches(pattern: "cli:*", principal: "cli:response"))
        #expect(Principal.matches(pattern: "*", principal: "cli:response"))
        #expect(!Principal.matches(pattern: "cli:response", principal: "cli:capture"))
        #expect(!Principal.matches(pattern: "admin:*", principal: "cli:response"))
    }
    
    @Test("Workflow names also match by pattern")
    func workflowPattern() {
        #expect(WorkflowPattern.matches(pattern: "capture", name: "capture"))
        #expect(WorkflowPattern.matches(pattern: "query.*", name: "query.foo"))
        #expect(WorkflowPattern.matches(pattern: "bank-*", name: "bank-jira-sync"))
        #expect(WorkflowPattern.matches(pattern: "*", name: "anything"))
        #expect(!WorkflowPattern.matches(pattern: "capture", name: "consolidate"))
        #expect(!WorkflowPattern.matches(pattern: "query.*", name: "search.foo"))
        #expect(!WorkflowPattern.matches(pattern: "bank-*", name: "consolidate"))
    }
    
    @Test("Basic allow decision")
    func allowsBasic() async throws {
        // Given
        let directory = try temporary.make("basic")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePolicy(#"""
        "cli:response":
          - capture
          - search
        """#, named: "workflow.yaml", in: directory)
        let store = PolicyStore(directory: directory)

        // When
        let allowed = await store.allows(principal: "cli:response", workflow: "capture")
        let denied = await store.allows(principal: "cli:response", workflow: "consolidate")
        let other = await store.allows(principal: "cli:capture", workflow: "capture")

        // Then
        #expect(allowed)
        #expect(!denied)
        #expect(!other)
    }
    
    @Test("Policies from multiple files merge as a union")
    func unionMerge() async throws {
        // Given
        let directory = try temporary.make("union")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePolicy(#"""
        "cli:response":
          - capture
        """#, named: "a.yaml", in: directory)
        try writePolicy(#"""
        "cli:response":
          - search
        "cli:*":
          - query
        """#, named: "b.yaml", in: directory)
        let store = PolicyStore(directory: directory)

        // When
        let snapshot = await store.catalog().policy

        // Then
        #expect(Set(snapshot["cli:response"] ?? []) == ["capture", "search"])
        #expect(snapshot["cli:*"] == ["query"])
        let qOk = await store.allows(principal: "cli:capture", workflow: "query")
        #expect(qOk, "the cli:* pattern must match cli:capture")
    }
    
    @Test("File changes are re-read")
    func hotReload() async throws {
        let directory = try temporary.make("reload")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePolicy(#"""
        "cli:x":
          - a
        """#, named: "p.yaml", in: directory)
        let store = PolicyStore(directory: directory)
        let allowsA = await allows(store, "cli:x", "a"); #expect(allowsA)
        let allowsBBefore = await allows(store, "cli:x", "b"); #expect(!allowsBBefore)
        try await Task.sleep(for: .seconds(1))
        try writePolicy(#"""
        "cli:x":
          - a
          - b
        """#, named: "p.yaml", in: directory)
        let allowsBAfter = await allows(store, "cli:x", "b"); #expect(allowsBAfter)
    }
    
    @Test("Without a policy directory, nothing is allowed")
    func noDirectoryAllowsNothing() async throws {
        let store = PolicyStore(directory: nil)
        let result = await allows(store, "cli:any", "x"); #expect(!result)
    }
    
    @Test("Policies in subfolders are also read")
    func subfolderPolicyLoads() async throws {
        // Given
        let directory = try temporary.make("subfolder")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sub = directory.appendingPathComponent("team")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try writePolicy(#"""
        "scheduler:bank":
          - bank-sync
        """#, named: "bank.yaml", in: sub)
        let store = PolicyStore(directory: directory)

        // When
        let allowed = await store.allows(principal: "scheduler:bank", workflow: "bank-sync")

        // Then
        #expect(allowed, "the subfolder policy (team/bank.yaml) must load via the recursive scan")
    }
    
    @Test("Files starting with a dot are not read as policy")
    func hiddenDotfilePolicyExcluded() async throws {
        // Given
        let directory = try temporary.make("hidden")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePolicy(#"""
        "cli:sneaky":
          - "*"
        """#, named: ".sneaky.yaml", in: directory)
        let store = PolicyStore(directory: directory)

        // When
        let result = await allows(store, "cli:sneaky", "anything")

        // Then
        #expect(!result, "leading-dot hidden files are excluded via skipsHiddenFiles (consistent with the write gate isStoreSafeID)")
    }
    
    @Test("A broken file surfaces via failures and valid files keep loading")
    func surfacesDecodeFailure() async throws {
        // Given
        let directory = try temporary.make("decode-failure")
        try "cli:*: [ok-wf]\n".write(
            to: directory.appendingPathComponent("good.yaml"), atomically: true, encoding: .utf8)
        try ": [broken".write(
            to: directory.appendingPathComponent("broken.yaml"), atomically: true, encoding: .utf8)
        let store = PolicyStore(directory: directory)

        // When
        let failures = await store.catalog().failures

        // Then
        #expect(failures.map(\.path) == ["broken.yaml"])
        #expect(await store.allows(principal: "cli:x", workflow: "ok-wf"), "valid files keep loading")
    }


    // MARK: - Private
    
    private func writePolicy(_ yaml: String, named filename: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(filename)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func allows(_ store: PolicyStore, _ principal: String, _ workflow: String) async -> Bool {
        await store.allows(principal: principal, workflow: workflow)
    }
}
