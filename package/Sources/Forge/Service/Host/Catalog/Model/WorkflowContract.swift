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
    // The hints and the defaults are keyed by the parameter's spelling.
    init(of signature: Signature, hints: [String: String], defaults: [String: JSONValue]) {
        self.inputs = signature.parameters.map { parameter in
            Input(
                name: parameter.name.spelling,
                type: parameter.type.rendered,
                defaultValue: defaults[parameter.name.spelling],
                hint: hints[parameter.name.spelling]
            )
        }
        self.returns = signature.returns.rendered
    }

    // MARK: - Public
    // MARK: - Private
}
