//
//  DispatchAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// Asks the daemon for an isolated run of a catalog workflow: its own lifetime,
// policy check and slot, where a `call` stays inside this run. The daemon
// settles the inputs against the target's signature.
struct DispatchAction: ForgeAction {
    enum Parameters: Int, ParameterSet {
        case name
        case inputs
        case timeout

        // MARK: - Property
        var declared: Parameter {
            switch self {
            case .name:
                Parameter(name: "name", type: .string)

            case .inputs:
                Parameter(name: "inputs", type: .dictionary(key: .string, value: .any))

            case .timeout:
                Parameter(name: "timeout", type: .optional(.double))
            }
        }

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func act(_ invocation: Warp.Invocation<Self>, in environment: ForgeEnvironment) async throws -> Warp.Value {
        let name = ValueBridge.text(invocation[.name])
        let inputs = try ValueBridge.fields(invocation[.inputs])

        return try await withDeadline(seconds: ValueBridge.number(invocation[.timeout])) {
            try await environment.dispatcher.dispatch(name: name, inputs: inputs)
        }
    }

    // MARK: - Private
}
