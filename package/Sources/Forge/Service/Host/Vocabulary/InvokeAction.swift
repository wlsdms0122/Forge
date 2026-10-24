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
struct InvokeAction: ForgeAction {
    enum Parameters: Int, ParameterSet {
        case model
        case allowed
        case envExtra
        case cwd
        case permissionMode
        case shareSession
        case timeout
        case body

        // MARK: - Property
        var declared: Parameter {
            switch self {
            case .model:
                Parameter(name: "model", type: .optional(.string))

            case .allowed:
                Parameter(name: "allowed", type: .optional(.array(.any)))

            case .envExtra:
                Parameter(name: "env_extra", type: .dictionary(key: .string, value: .string))

            case .cwd:
                Parameter(name: "cwd", type: .optional(.string))

            case .permissionMode:
                Parameter(name: "permission_mode", type: .optional(.string))

            case .shareSession:
                Parameter(name: "share_session", type: .bool)

            case .timeout:
                Parameter(name: "timeout", type: .optional(.double))

            case .body:
                Parameter(
                    name: "body",
                    type: .procedure(ProcedureType(returns: InvokeAction.result, failing: .anything))
                )
            }
        }

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    // What the body returns, which is what the session returns.
    static let result = TypeExpression.parameter(name: "Result")

    static let signature = Signature(of: Self.self, returns: result, failing: .anything, isolation: .isolated)

    // MARK: - Initializer
    // MARK: - Public
    func act(_ invocation: Warp.Invocation<Self>, in environment: ForgeEnvironment) async throws -> Warp.Value {
        // The body is a closure so that nothing in it runs before the session
        // is open.
        guard case let .procedure(body) = invocation[.body] else {
            throw ExecutionError("invoke has no body")
        }

        let settings = AgentSessionSettings(
            model: invocation.string(.model),
            allowed: invocation[.allowed],
            cwd: try Self.nonEmpty(invocation.string(.cwd), field: "cwd"),
            permissionMode: try Self.nonEmpty(invocation.string(.permissionMode), field: "permission_mode"),
            envExtra: try ValueBridge.strings(invocation[.envExtra]),
            shareSession: invocation[.shareSession] == .bool(true)
        )

        return try await withDeadline(seconds: ValueBridge.number(invocation[.timeout])) {
            try await environment.agent.withSession(settings) {
                try await invocation.call(body)
            }
        }
    }

    // MARK: - Private
    // null means "unset" and stays nil; an empty string is an author mistake, not
    // a quiet fallback into the daemon's own working directory.
    private static func nonEmpty(_ string: String?, field: String) throws -> String? {
        guard string != "" else {
            throw ExecutionError(
                "invoke: \(field) must be a non-empty string, or omitted/null to"
                    + " mean \"unset\" — got an empty string"
            )
        }

        return string
    }
}
