//
//  RunAction.swift
//  Forge
//
//  Created by JSilver on 10/22/26.
//

import Foundation
import Warp

// Which run this is: its own id and the id of the run that started the chain.
struct RunAction: Warp.Effect {
    typealias Parameters = NoParameters

    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func run(_ invocation: Warp.Invocation<Self>) async throws -> Warp.Value {
        let environment = try ForgeEnvironment.from(invocation)

        return try Value.holding(
            [
                (name: "workflow_id", value: .string(environment.runID)),
                (name: "root_id", value: .string(environment.rootID))
            ],
            named: ForgeVocabulary.runType
        )
    }

    // MARK: - Private
}
