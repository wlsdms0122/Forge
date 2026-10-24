//
//  LocateAction.swift
//  Forge
//
//  Created by JSilver on 10/22/26.
//

import Foundation
import Warp

// Where a resource file is, as an absolute path.
struct LocateAction: ForgeAction {
    enum Parameters: Int, ParameterSet {
        case path

        // MARK: - Property
        var declared: Parameter { Parameter(name: "path", type: .string) }

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    static let signature = Signature(of: Self.self, returns: .string, isolation: .isolated)

    // MARK: - Initializer
    // MARK: - Public
    func act(_ invocation: Warp.Invocation<Self>, in environment: ForgeEnvironment) async throws -> Warp.Value {
        return .string(try await environment.resources.locate(ValueBridge.text(invocation[.path])))
    }

    // MARK: - Private
}
