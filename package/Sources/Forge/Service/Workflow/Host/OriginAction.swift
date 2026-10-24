//
//  OriginAction.swift
//  Forge
//
//  Created by JSilver on 10/22/26.
//

import Foundation
import Warp

// What started this run: its kind, and the id of the schedule or caller where
// there is one.
struct OriginAction: ForgeAction {
    typealias Parameters = NoParameters

    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func act(_ invocation: Warp.Invocation<Self>, in environment: ForgeEnvironment) async throws -> Warp.Value {
        return try Value.holding(
            [
                (name: "kind", value: .string(environment.origin.kind)),
                (name: Name("id"), value: environment.origin.id.map { id in Value.string(id) } ?? .null)
            ],
            named: ForgeVocabulary.originType
        )
    }

    // MARK: - Private
}
