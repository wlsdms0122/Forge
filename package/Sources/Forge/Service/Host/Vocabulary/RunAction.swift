//
//  RunAction.swift
//  Forge
//
//  Created by JSilver on 10/22/26.
//

import Foundation
import Warp

// Which run this is: its own id and the id of the run that started the chain.
struct RunAction: ForgeAction {
    typealias Parameters = NoParameters

    // MARK: - Property
    static let signature = Signature(of: Self.self, returns: .named(ForgeVocabulary.runType), isolation: .isolated)

    // MARK: - Initializer
    // MARK: - Public
    func act(_ invocation: Invocation<Self>, in environment: ForgeEnvironment) async throws -> Warp.Value {
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
