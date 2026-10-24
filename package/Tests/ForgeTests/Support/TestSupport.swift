//
//  TestSupport.swift
//  ForgeTests
//
//  Created by JSilver on 10/25/26.
//

import Foundation
import Testing
@testable import Forge

// A command pattern that tests write in as literals.
//
// Because the tokens are literals, a failure means an input typo, not a defect in the
// subject. Instead of dying with `try!`, raise via `#require` so the report shows which
// token was the problem.
func commandPattern(
    _ tokens: [String],
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> CommandPattern {
    try #require(try CommandPattern(tokens: tokens), sourceLocation: sourceLocation)
}

// A workflow file declaring one public procedure named after the file, with
// the body's lines as that procedure's keys. Tests write a procedure body
// because what they are about is the forge word inside it, not the shape of
// the file.
func workflowFile(_ body: String, named name: String) -> String {
    let procedure = body
        .split(separator: "\n", omittingEmptySubsequences: false)
        .drop { line in line.trimmingCharacters(in: .whitespaces).isEmpty }
        .map { line in line.isEmpty ? "" : "    \(line)" }
        .joined(separator: "\n")

    return """
    procedures:
      \(name):
        access: public
    \(procedure)
    """
}
