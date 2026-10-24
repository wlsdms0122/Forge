//
//  ResourceAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// A resource file rendered as a template over the inputs handed with it.
struct ResourceAction: Warp.Effect {
    enum Parameters: Int, ParameterSet {
        case content
        case inputs

        // MARK: - Property
        var declared: Parameter {
            switch self {
            case .content:
                Parameter(name: "content", type: .string)

            case .inputs:
                Parameter(name: "inputs", type: .dictionary(key: .string, value: .any))
            }
        }

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func run(_ invocation: Warp.Invocation<Self>) async throws -> Warp.Value {
        let environment = try ForgeEnvironment.from(invocation)
        let body = try await environment.resources.read(invocation.string(.content) ?? "")

        return .string(
            try ResourceTemplate(body).rendered(over: try ValueBridge.fields(invocation[.inputs]))
        )
    }

    // MARK: - Private
}
