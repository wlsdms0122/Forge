//
//  PolicyPatternValidationTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("PolicyPatternValidation Tests")
struct PolicyPatternValidationTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("What the policy pattern grammar accepts and rejects")
    func grammar() {
        #expect(Principal.isValidPattern("*"))
        #expect(Principal.isValidPattern("cli:code-review"))
        #expect(Principal.isValidPattern("cli:*"))
        #expect(!Principal.isValidPattern("cli:code*"), "interior/partial wildcards are outside the grammar")
        #expect(!Principal.isValidPattern("*:x"))
        #expect(WorkflowPattern.isValidPattern("*"))
        #expect(WorkflowPattern.isValidPattern("bank-*"))
        #expect(!WorkflowPattern.isValidPattern("*audit"))
        #expect(!WorkflowPattern.isValidPattern("qu*ery"))
    }
    
    @Test("A grant that reaches no one is excluded, and the fact is surfaced")
    func deadGrantIsExcludedAndSurfaced() async throws {
        // Given
        let directory = try makePolicyDir("""
        "cli:ok": [bank-*]
        "cli:typo*": [anything]
        "cli:half": ["*audit", "query.*"]
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PolicyStore(directory: directory)

        // When
        let allowed = await store.allows(principal: "cli:ok", workflow: "bank-release")

        // Then
        #expect(allowed)
        let half = await store.allows(principal: "cli:half", workflow: "query.search")
        #expect(half, "the same principal's valid pattern must survive")
        let typo = await store.allows(principal: "cli:typoX", workflow: "anything")
        #expect(!typo)
        let failures = await store.catalog().failures
        #expect(failures.count == 2, "\(failures.map(\.reason))")
        #expect(failures.contains { failure in failure.reason.contains("cli:typo*") })
        #expect(failures.contains { failure in failure.reason.contains("*audit") })
    }
    
    // MARK: - Private
    private func makePolicyDir(_ yaml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("forge-pol-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try yaml.write(to: directory.appendingPathComponent("p.yaml"), atomically: true, encoding: .utf8)
        
        return directory
    }
}
