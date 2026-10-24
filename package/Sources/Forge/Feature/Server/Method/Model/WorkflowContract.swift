//
//  WorkflowContract.swift
//  Forge
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import Warp

struct WorkflowContract {
    // MARK: - Property
    // MARK: - Initializer
    init() {
    }

    // MARK: - Public
    // What a caller fills in, each with the hint the file writes beside it
    // and the default it writes, as the file writes it, which an omitted
    // argument becomes. An input whose file writes no default reports none.
    func inputs(of signature: Signature, hints: [Name: String], defaults: [Name: Value]) -> [String: Any] {
        Dictionary(
            signature.parameters.map { parameter in
                var described: [String: Any] = ["type": parameter.type.rendered]

                if let written = defaults[parameter.name] {
                    described["default"] = jsonValueToAny(ValueBridge.json(written))
                }

                if let hint = hints[parameter.name] { described["hint"] = hint }

                return (parameter.name.spelling, described)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // What a run returns.
    func returns(of signature: Signature) -> String {
        signature.returns.rendered
    }

    // MARK: - Private
}
