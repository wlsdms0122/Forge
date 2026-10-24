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
        let entry = try Name(name)

        guard let procedure = module.procedures[entry] else {
            throw WorkflowValidationError("workflow '\(name)' declares no procedure of that name")
        }

        self.name = name
        self.description = documentation?.descriptions[entry]
        self.contract = WorkflowContract(
            of: procedure.signature,
            hints: documentation?.hints[entry] ?? [:],
            defaults: documentation?.defaults[entry] ?? [:]
        )
        self.module = module
    }

    // MARK: - Public
    // MARK: - Private
}
