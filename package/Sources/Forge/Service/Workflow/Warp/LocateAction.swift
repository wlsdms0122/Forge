//
//  LocateAction.swift
//  Forge
//
//  Created by JSilver on 10/22/26.
//

import Foundation
import Warp

// Where a resource file is, as an absolute path.
struct LocateAction: Warp.Effect {
    enum Parameters: Int, ParameterSet {
        case path

        // MARK: - Property
        var declared: Parameter { Parameter(name: "path", type: .string) }

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func run(_ invocation: Warp.Invocation<Self>) async throws -> Warp.Value {
        let environment = try ForgeEnvironment.from(invocation)

        return .string(try await environment.resources.locate(ValueBridge.text(invocation[.path])))
    }

    // MARK: - Private
}
