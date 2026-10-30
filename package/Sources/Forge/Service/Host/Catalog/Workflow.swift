//
//  Workflow.swift
//  Forge
//
//  Created by JSilver on 10/24/26.
//

import Foundation
import Warp
import WarpYAML

// A workflow the catalog hands out: its path under the root, or the inline
// sigil in its place, the prose its file writes beside its entry,
// the contract a caller fills in, and the module the host runs.
struct Workflow: Sendable {
    // MARK: - Property
    // The procedure a run starts from.
    static let entry = "main"

    let path: String
    let description: String?
    let contract: WorkflowContract
    let module: Warp.Module

    // MARK: - Initializer
    // The entry is the workflow; an inline spec has no documentation.
    init(path: String, module: Warp.Module, documentation: Documentation?) throws {
        guard let procedure = module.procedures[try Warp.Name(Self.entry)] else {
            throw WorkflowValidationError("workflow '\(path)' declares no procedure '\(Self.entry)'")
        }

        let entry = try WarpYAML.Name(Self.entry)
        let hints = documentation?.hints[entry] ?? [:]

        self.path = path
        self.description = documentation?.descriptions[entry]
        self.contract = WorkflowContract(
            of: procedure.signature,
            hints: Dictionary(uniqueKeysWithValues: hints.map { parameter, hint in (parameter.spelling, hint) })
        )
        self.module = module
    }

    // MARK: - Public
    // MARK: - Private
}
