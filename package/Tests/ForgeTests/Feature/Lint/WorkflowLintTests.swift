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
        let report = try check(named: "stale", yaml: """
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
        let report = try check(named: "sanctioned", yaml: """
        parameters: [ who: String ]
        returns: String
        result: { format: "hi ${who}", with: { who: { ref: who } } }
        """)

        // Then
        #expect(report.ok, "\(report.issues)")
    }

    // MARK: - Private
    private func check(named name: String, yaml: String) throws -> WorkflowLint.Report {
        let directory = try temporary.make("lint-\(name)")
        let file = directory.appendingPathComponent("\(name).yaml")

        try workflowFile(yaml, named: name).write(to: file, atomically: true, encoding: .utf8)

        return WorkflowLint.check(path: file.path)
    }
}
