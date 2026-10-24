//
//  AgentAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// A single prompt turn against the agent session `invoke` opened.
struct AgentAction: ForgeAction {
    enum Parameters: Int, ParameterSet {
        case prompt

        // MARK: - Property
        var declared: Parameter { Parameter(name: "prompt", type: .string) }

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    static let signature = Signature(
        of: Self.self,
        returns: .string,
        failing: .these([BackendNonzeroExit.type]),
        isolation: .isolated
    )

    // MARK: - Initializer
    // MARK: - Public
    func act(_ invocation: Invocation<Self>, in environment: ForgeEnvironment) async throws -> Warp.Value {
        let prompt = ValueBridge.text(invocation[.prompt])

        return try await environment.withStepSlot {
            .string(try await environment.capabilities.agent.send(prompt: prompt))
        }
    }

    // MARK: - Private
}
