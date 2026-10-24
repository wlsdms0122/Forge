//
//  ForgeAction.swift
//  Forge
//
//  Created by JSilver on 10/24/26.
//

import Foundation
import Warp

// A native verb that acts outside the program. Each run of one is the step
// of the verb it serves, announced from here: started when it starts, and
// completed with what it returns or failed with what it throws.
protocol ForgeAction: Warp.Effect {
    func act(_ invocation: Warp.Invocation<Self>, in environment: ForgeEnvironment) async throws -> Warp.Value
}

extension ForgeAction {
    func run(_ invocation: Warp.Invocation<Self>) async throws -> Warp.Value {
        let environment = try ForgeEnvironment.from(invocation)

        return try await environment.bridge.step(of: invocation) {
            try await act(invocation, in: environment)
        }
    }
}
