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
// A workflow file declaring one public procedure named after the file, with
// the body's lines as that procedure's keys.
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
