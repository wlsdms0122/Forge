//
//  WorkflowLintTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("WorkflowLint Tests")
struct WorkflowLintTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("lint")

    // MARK: - Initializer
    // MARK: - Test
    @Test("lint flags old-syntax ${} strings loudly — the language may stay silent, but the authoring-file gate does not")
    func staleTemplateStringFlagged() async throws {
        // Given
        let report = try await check(named: "stale", yaml: """
        returns: String
        body:
          - let: greet
            value: "hello, ${who}"
        result: { ref: greet }
        """)

        // Then
        #expect(!report.ok)
        #expect(report.issues.contains { issue in issue.contains("${") }, "\(report.issues)")
    }

    @Test("${} is legitimate in a format template")
    func sanctionedSurfacesPass() async throws {
        // Given
        let report = try await check(named: "sanctioned", yaml: """
        parameters: [ who: String ]
        returns: String
        result: { format: "hi ${who}", with: { who: { ref: who } } }
        """)

        // Then
        #expect(report.ok, "\(report.issues)")
    }

    @Test("${} under a nameless statement is flagged, since value: is a statement, not a quotation")
    func staleTemplateUnderNamelessStatementFlagged() async throws {
        // Given
        let report = try await check(named: "nameless", yaml: """
        failing: [aborted]
        body:
          - value: { abort: "failed for ${who}" }
        """)

        // Then
        #expect(report.issues.contains { issue in issue.contains("body[0].value.abort") }, "\(report.issues)")
    }

    @Test("${} in a description or a hint is prose beside the document")
    func proseKeysPass() async throws {
        // Given
        let report = try await check(named: "prose", yaml: """
        description: "renders ${who}"
        parameters: [ who: { type: String, hint: "the ${name} to greet" } ]
        returns: String
        result: { ref: who }
        """)

        // Then
        #expect(report.ok, "\(report.issues)")
    }

    @Test("files checked together lean on each other, so a call to another workflow by name reads with that workflow's file")
    func filesCheckedTogetherLeanOnEachOther() async throws {
        // Given
        let directory = try temporary.make("lint-together")
        let caller = directory.appendingPathComponent("caller.yaml")
        let callee = directory.appendingPathComponent("callee.yaml")

        try workflowFile("""
        returns: Int
        result: { call: { procedure: callee, arguments: { base: 1 } } }
        """, named: "caller").write(to: caller, atomically: true, encoding: .utf8)
        try workflowFile("""
        parameters: [ base: Int ]
        returns: Int
        result: { ref: base }
        """, named: "callee").write(to: callee, atomically: true, encoding: .utf8)

        // When
        let together = await WorkflowLint.check(paths: [caller.path, callee.path])
        let alone = await WorkflowLint.check(paths: [caller.path])

        // Then
        #expect(together.map(\.ok) == [true, true])
        #expect(alone.first?.refusal?.contains("'callee' is not declared by a document this text leans on") == true)
    }

    @Test("a file that loads and does not build fails the check, as the daemon leaves it out of its catalog")
    func aFileTheBuildRefusesFails() async throws {
        // Given
        let report = try await check(named: "unbuilt", yaml: """
        returns: Int
        result: text
        """)

        // Then
        #expect(report.refusal?.hasPrefix("build: ") == true, "\(String(describing: report.refusal))")
    }

    // MARK: - Private
    private func check(named name: String, yaml: String) async throws -> WorkflowLint.Report {
        let directory = try temporary.make("lint-\(name)")
        let file = directory.appendingPathComponent("\(name).yaml")

        try workflowFile(yaml, named: name).write(to: file, atomically: true, encoding: .utf8)

        return try #require(await WorkflowLint.check(paths: [file.path]).first)
    }
}
