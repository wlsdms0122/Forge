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
    // An input with the hint the file writes beside it.
    struct Input: Sendable {
        // MARK: - Property
        let name: String
        let type: String
        let hint: String?

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let inputs: [Input]
    let returns: String

    // MARK: - Initializer
    // The hints are keyed by the parameter's spelling.
    init(of signature: Signature, hints: [String: String]) {
        self.inputs = signature.parameters.map { parameter in
            Input(
                name: parameter.name.spelling,
                type: parameter.type.rendered,
                hint: hints[parameter.name.spelling]
            )
        }
        self.returns = signature.returns.rendered
    }

    // MARK: - Public
    // MARK: - Private
}
