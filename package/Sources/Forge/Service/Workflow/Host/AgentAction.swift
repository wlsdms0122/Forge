//
//  AgentAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

// A single prompt turn against the ambient agent session — invoke opens the
// session; an agent step outside one is an authoring error.
struct AgentAction: Spec.Action {
    // MARK: - Property
    static let key = "agent"

    let prompt: Spec.Reference

    var referencedPaths: [[PathSegment]] { prompt.referencedPaths }

    // MARK: - Initializer
    init(prompt: Spec.Reference) {
        self.prompt = prompt
    }

    init(from decoder: Decoder) throws {
        self.prompt = try Spec.Reference(from: decoder)
    }

    // MARK: - Public
    func run(_ context: ActionContext) async throws -> Spec.Value {
        let host = try ForgeHost.from(context)
        let prompt = try context.resolver.string(prompt)

        return try await host.withStepSlot {
            .string(try await host.agent.send(prompt: prompt))
        }
    }

    func encode(to encoder: Encoder) throws {
        try prompt.encode(to: encoder)
    }

    // MARK: - Private
}
