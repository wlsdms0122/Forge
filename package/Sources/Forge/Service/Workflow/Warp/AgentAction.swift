//
//  AgentAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// A single prompt turn against the ambient agent session — invoke opens the
// session; an agent step outside one is an authoring error.
struct AgentAction: Warp.Effect {
    // MARK: - Property


    // MARK: - Initializer
    // MARK: - Public
    func run(_ invocation: Warp.Invocation) async throws -> Warp.Value {
        let environment = try ForgeEnvironment.from(invocation)
        let prompt = try invocation.string("prompt") ?? ""

        return try await environment.withStepSlot {
            .string(try await environment.agent.send(prompt: prompt))
        }
    }

    // MARK: - Private
}
