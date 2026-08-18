//
//  DispatchAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// Asks the daemon for an isolated run — an effect with its own lifetime, ACL
// and slot, not a language call. `use` is the function call; this is
// Process.run. Exactly one of `name` (catalog) or `spec` (inline) names the
// target; the daemon settles inputs against the target's signature.
struct DispatchAction: Warp.Effect {
    // MARK: - Property


    // MARK: - Initializer
    // MARK: - Public
    func run(_ invocation: Warp.Invocation) async throws -> Warp.Value {
        let environment = try ForgeEnvironment.from(invocation)
        let target = try invocation.string("name")
        let inline = try invocation.resolve("spec")
        let timeout = ValueBridge.number(try invocation.resolve("timeout"))

        let settled: [String: Warp.Value]

        if case .object(let inputs) = try invocation.resolve("inputs") {
            settled = inputs
        } else {
            settled = [:]
        }

        return try await withDeadline(seconds: timeout) {
            try await environment.dispatcher.dispatch(
                name: target,
                inline: inline == .null ? nil : inline,
                inputs: settled
            )
        }
    }

    // MARK: - Private
}
