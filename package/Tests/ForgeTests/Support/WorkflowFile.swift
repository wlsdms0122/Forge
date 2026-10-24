//
//  WorkflowFile.swift
//  ForgeTests
//
//  Created by JSilver on 8/17/26.
//

import Foundation

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
