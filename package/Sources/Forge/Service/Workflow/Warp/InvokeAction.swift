//
//  InvokeAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// The agent session envelope — not a plain group. It resolves the session
// settings (model, permissions, cwd, ...) at its boundary, opens the ambient
// session through the environment, and runs its steps inside; `agent` steps only make
// sense in here.
struct InvokeAction: Warp.Effect {
    // MARK: - Property


    // MARK: - Initializer
    // MARK: - Public
    func run(_ invocation: Warp.Invocation) async throws -> Warp.Value {
        let environment = try ForgeEnvironment.from(invocation)
        let resolver = invocation.resolver

        // The body is a block argument rather than a value one: it must not be
        // evaluated until the session is open.
        guard let steps = invocation.block("steps") else {
            throw ExecutionError("invoke has no steps")
        }

        var envExtra: [String: String] = [:]

        if case .object(let written) = try invocation.resolve("env_extra") {
            envExtra = written.mapValues(resolver.stringify)
        }

        let settings = AgentSessionSettings(
            model: try invocation.string("model"),
            allowed: try invocation.resolve("allowed"),
            cwd: try Self.optionalNonEmptyString(
                try invocation.resolve("cwd"),
                field: "cwd"
            ),
            permissionMode: try Self.optionalNonEmptyString(
                try invocation.resolve("permission_mode"),
                field: "permission_mode"
            ),
            envExtra: envExtra,
            shareSession: try Self.share(try invocation.resolve("share_session"))
        )
        let timeout = ValueBridge.number(try invocation.resolve("timeout"))
        let block = steps.block
        let scope = invocation.scope

        return try await withDeadline(seconds: timeout) {
            try await environment.agent.withSession(settings) {
                try await invocation.run(block, in: scope)
            }
        }
    }

    // MARK: - Private
    private static func share(_ value: Warp.Value) throws -> Bool {
        switch value {
        case .null:
            return false

        case .bool(let share):
            return share

        case let other:
            throw ExecutionError(
                "invoke.share_session must resolve to a bool or null,"
                    + " got \(other.type)"
            )
        }
    }

    // null means "unset" and stays nil; an empty string is an author mistake, not
    // a quiet fallback into the daemon's own working directory.
    private static func optionalNonEmptyString(
        _ value: Warp.Value,
        field: String
    ) throws -> String? {
        switch value {
        case .null:
            return nil

        case .string(let string):
            guard !string.isEmpty else {
                throw ExecutionError(
                    "invoke: \(field) must be a non-empty string, or omitted/null to"
                        + " mean \"unset\" — got an empty string"
                )
            }

            return string

        case let other:
            throw ExecutionError(
                "invoke: \(field) must resolve to a string or null, got \(other.type)"
            )
        }
    }
}
