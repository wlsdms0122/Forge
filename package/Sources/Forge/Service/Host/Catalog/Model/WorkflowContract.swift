//
//  WorkflowContract.swift
//  Forge
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import Warp

// What a caller fills in and what a run returns, each type as the language
// renders it.
struct WorkflowContract: Sendable {
    // An input with the hint the file writes beside it and the default it
    // writes, which an omitted argument becomes. An input whose file writes
    // no default has none.
    struct Input: Sendable {
        // MARK: - Property
        let name: String
        let type: String
        let defaultValue: JSONValue?
        let hint: String?

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let inputs: [Input]
    let returns: String

    // MARK: - Initializer
    init(of signature: Signature, hints: [Name: String], defaults: [Name: Value]) {
        self.inputs = signature.parameters.map { parameter in
            Input(
                name: parameter.name.spelling,
                type: parameter.type.rendered,
                defaultValue: defaults[parameter.name].flatMap { value in try? ValueBridge.json(value) },
                hint: hints[parameter.name]
            )
        }
        self.returns = signature.returns.rendered
    }

    // MARK: - Public
    // MARK: - Private
}
