//
//  Workflow.swift
//  Forge
//
//  Created by JSilver on 10/24/26.
//

import Foundation
import Warp
import WarpYAML

// A workflow the catalog hands out: the name a run starts from, the prose
// its file writes beside it, the contract a caller fills in, and the module
// the host runs.
struct Workflow: Sendable {
    // MARK: - Property
    let name: String
    let description: String?
    let contract: WorkflowContract
    let module: Warp.Module

    // MARK: - Initializer
    // The procedure declared under the name is the workflow; an inline spec
    // has no documentation.
    init(name: String, module: Warp.Module, documentation: Documentation?) throws {
        guard let procedure = module.procedures[try Warp.Name(name)] else {
            throw WorkflowValidationError("workflow '\(name)' declares no procedure of that name")
        }

        let entry = try WarpYAML.Name(name)
        let hints = documentation?.hints[entry] ?? [:]
        let defaults = documentation?.defaults[entry] ?? [:]

        self.name = name
        self.description = documentation?.descriptions[entry]
        self.contract = WorkflowContract(
            of: procedure.signature,
            hints: Dictionary(uniqueKeysWithValues: hints.map { parameter, hint in (parameter.spelling, hint) }),
            defaults: Dictionary(
                uniqueKeysWithValues: defaults.map { parameter, written in (parameter.spelling, JSONValue(written)) }
            )
        )
        self.module = module
    }

    // MARK: - Public
    // MARK: - Private
}
