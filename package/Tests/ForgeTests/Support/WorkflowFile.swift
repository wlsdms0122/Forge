//
//  WorkflowFile.swift
//  ForgeTests
//
//  Created by JSilver on 8/17/26.
//

import Foundation

// A workflow file is a module declaring one procedure named after the file.
//
// Tests here write a procedure body — parameters, body, result — because what they
// are about is the forge word inside it, not the shape of the file. This puts
// the envelope on. What the envelope itself accepts is Warp's own
// `ModuleNotationTests`; what Forge additionally requires of a workflow file
// (exactly one procedure, named after the file) is `CatalogGenerationTests`.
func workflowFile(_ body: String, named name: String) -> String {
    let lines = body
        .split(separator: "\n", omittingEmptySubsequences: false)
        .drop { line in line.trimmingCharacters(in: .whitespaces).isEmpty }

    // A `name:` written in the body was the document's metadata, and it has
    // moved out to the module — dropping it here is the same edit an author
    // makes when migrating a file.
    let procedure = lines
        .drop { line in line.hasPrefix("name:") }
        .map { line in line.isEmpty ? "" : "    \(line)" }
        .joined(separator: "\n")

    return """
    name: \(name)
    procedures:
      \(name):
    \(procedure)
    """
}
