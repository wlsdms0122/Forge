//
//  AgentServing.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// The agent session is ambient — `invoke` opens it, `agent` steps inside speak
// through it, and `parallel` children do not inherit it. The provider owns that
// scoping; actions only open sessions and send prompts.
protocol AgentServing: Sendable {
    func withSession(
        _ settings: AgentSessionSettings,
        body: @Sendable () async throws -> Warp.Value
    ) async throws -> Warp.Value

    func send(prompt: String) async throws -> String
}
