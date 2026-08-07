//
//  InvokeAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

// The agent session envelope — not a plain group. It resolves the session
// settings (model, permissions, cwd, ...) at its boundary, opens the ambient
// session through the host, and runs its steps inside; `agent` steps only make
// sense in here.
struct InvokeAction: Spec.Action {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case steps
        case model
        case allowed
        case cwd
        case output
        case envExtra = "env_extra"
        case permissionMode = "permission_mode"
        case shareSession = "share_session"
        case timeout
    }

    // MARK: - Property
    static let key = "invoke"

    let steps: [Spec.Step]
    let model: Spec.Reference?
    let allowed: Spec.Reference?
    let envExtra: [String: Spec.Reference]?
    let cwd: Spec.Reference?
    let permissionMode: Spec.Reference?
    let shareSession: Spec.Reference?
    let output: Spec.Reference?
    let timeout: Double?

    var scopeDeclarations: [ScopeDeclaration] {
        [ScopeDeclaration(
            label: "invoke.steps",
            steps: steps,
            trailingPaths: output?.referencedPaths ?? []
        )]
    }

    var referencedPaths: [[PathSegment]] {
        [model, allowed, cwd, permissionMode, shareSession]
            .compactMap { reference in reference }
            .flatMap(\.referencedPaths)
            + (envExtra?.values.flatMap(\.referencedPaths) ?? [])
    }

    // MARK: - Initializer
    init(
        steps: [Spec.Step],
        model: Spec.Reference? = nil,
        allowed: Spec.Reference? = nil,
        envExtra: [String: Spec.Reference]? = nil,
        cwd: Spec.Reference? = nil,
        permissionMode: Spec.Reference? = nil,
        shareSession: Spec.Reference? = nil,
        output: Spec.Reference? = nil,
        timeout: Double? = nil
    ) {
        self.steps = steps
        self.model = model
        self.allowed = allowed
        self.envExtra = envExtra
        self.cwd = cwd
        self.permissionMode = permissionMode
        self.shareSession = shareSession
        self.output = output
        self.timeout = timeout
    }

    init(from decoder: Decoder) throws {
        try Spec.KeyGate.rejectUnknownKeys(
            in: decoder,
            known: CodingKeys.self,
            context: "invoke"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.steps = try container.decode([Spec.Step].self, forKey: .steps)
        self.model = try container.decodeIfPresent(Spec.Reference.self, forKey: .model)
        self.allowed = try container.decodeIfPresent(Spec.Reference.self, forKey: .allowed)
        self.envExtra = try container.decodeIfPresent(
            [String: Spec.Reference].self,
            forKey: .envExtra
        )
        self.cwd = try container.decodeIfPresent(Spec.Reference.self, forKey: .cwd)
        self.permissionMode = try container.decodeIfPresent(
            Spec.Reference.self,
            forKey: .permissionMode
        )
        self.shareSession = try container.decodeIfPresent(
            Spec.Reference.self,
            forKey: .shareSession
        )
        self.output = try container.decodeIfPresent(Spec.Reference.self, forKey: .output)
        self.timeout = try container.decodeIfPresent(Double.self, forKey: .timeout)
    }

    // MARK: - Public
    func run(_ context: ActionContext) async throws -> Spec.Value {
        let host = try ForgeHost.from(context)
        let resolver = context.resolver
        let settings = AgentSessionSettings(
            model: try model.map { reference in try resolver.string(reference) },
            allowed: try allowed.map { reference in try resolver.resolve(reference) },
            cwd: try cwd.flatMap { reference in
                try Self.optionalNonEmptyString(resolver.resolve(reference), field: "cwd")
            },
            permissionMode: try permissionMode.flatMap { reference in
                try Self.optionalNonEmptyString(
                    resolver.resolve(reference),
                    field: "permission_mode"
                )
            },
            envExtra: try (envExtra ?? [:]).mapValues { reference in
                try resolver.string(reference)
            },
            shareSession: try shareSession.map { reference in
                switch try resolver.resolve(reference) {
                case .null:
                    return false

                case .bool(let share):
                    return share

                case let other:
                    throw ExecutionError(
                        "invoke.share_session must resolve to a bool or null,"
                            + " got \(other.typeName)"
                    )
                }
            } ?? false
        )
        let steps = self.steps
        let output = self.output
        let scope = context.scope

        return try await withHostDeadline(seconds: timeout) {
            try await host.agent.withSession(settings) {
                let result = try await context.run(steps, in: scope)

                guard let output else { return result.lastOutput }

                return try context.resolver(for: result.scope).resolve(output)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(steps, forKey: .steps)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(allowed, forKey: .allowed)
        try container.encodeIfPresent(envExtra, forKey: .envExtra)
        try container.encodeIfPresent(cwd, forKey: .cwd)
        try container.encodeIfPresent(permissionMode, forKey: .permissionMode)
        try container.encodeIfPresent(shareSession, forKey: .shareSession)
        try container.encodeIfPresent(output, forKey: .output)
        try container.encodeIfPresent(timeout, forKey: .timeout)
    }

    // MARK: - Private
    // null means "unset" and stays nil; an empty string is an author mistake, not
    // a quiet fallback into the daemon's own working directory.
    private static func optionalNonEmptyString(
        _ value: Spec.Value,
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
                "invoke: \(field) must resolve to a string or null, got \(other.typeName)"
            )
        }
    }
}
