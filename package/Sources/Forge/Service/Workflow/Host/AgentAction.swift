//
//  AgentAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// A single prompt turn against the agent session `invoke` opened.
struct AgentAction: Warp.Effect {
    enum Parameters: Int, ParameterSet {
        case prompt

        // MARK: - Property
        var declared: Parameter { Parameter(name: "prompt", type: .string) }

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func run(_ invocation: Warp.Invocation<Self>) async throws -> Warp.Value {
        let environment = try ForgeEnvironment.from(invocation)
        let prompt = ValueBridge.text(invocation[.prompt])

        return try await environment.withStepSlot {
            .string(try await environment.agent.send(prompt: prompt))
        }
    }

    // MARK: - Private
}
