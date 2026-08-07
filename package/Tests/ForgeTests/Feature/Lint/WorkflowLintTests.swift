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
        steps:
          - id: greet
            value: "hello, ${inputs.who}"
        """)

        // Then
        #expect(!report.ok)
        #expect(report.issues.contains { issue in issue.contains("${") }, "\(report.issues)")
    }

    @Test("${} is legitimate in { value: } quotation, format templates, and prose fields")
    func sanctionedSurfacesPass() async throws {
        // Given — quotation carries literal ${} on purpose; format is the
        // dialect's home; description/hint are prose
        let report = try check(named: "sanctioned", yaml: """
        description: use ${x} spelling in templates
        inputs:
          who:
            type: string
            hint: interpolated via ${who}
        steps:
          - id: greet
            value: { format: "hi ${who}", with: { who: { ref: inputs.who } } }
          - id: doc
            value: { value: "literal ${kept} text" }
        """)

        // Then
        #expect(report.ok, "\(report.issues)")
    }

    // MARK: - Private
    private func check(named name: String, yaml: String) throws -> WorkflowLint.Report {
        let directory = try temporary.make("lint-\(name)")
        let file = directory.appendingPathComponent("\(name).yaml")

        try yaml.write(to: file, atomically: true, encoding: .utf8)

        return WorkflowLint.check(path: file.path)
    }
}
