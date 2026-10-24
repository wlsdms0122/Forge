//
//  ResourceAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// A resource file rendered as a template over the inputs handed with it.
struct ResourceAction: ForgeAction {
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
    static let signature = Signature(of: Self.self, returns: .string, isolation: .isolated)

    // MARK: - Initializer
    // MARK: - Public
    func act(_ invocation: Invocation<Self>, in environment: ForgeEnvironment) async throws -> Warp.Value {
        let body = try await environment.capabilities.resources.read(ValueBridge.text(invocation[.content]))

        return .string(
            try ResourceTemplate(body).rendered(over: try ValueBridge.fields(invocation[.inputs]))
        )
    }

    // MARK: - Private
}
