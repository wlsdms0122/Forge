//
//  LiveAgent.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// The live agent seam over forge's invoke executor. The session is ambient —
// `withSession` binds it to the task and `send` speaks through whatever session
// the current task carries, so the session follows structured concurrency's
// task-local scoping.
struct LiveAgent: AgentServing {
    // MARK: - Property
    let executor: AgentExecutor

    // MARK: - Initializer
    init(executor: AgentExecutor) {
        self.executor = executor
    }

    // MARK: - Public
    func withSession(
        _ settings: AgentSessionSettings,
        body: @Sendable () async throws -> Warp.Value
    ) async throws -> Warp.Value {
        // share_session is a conditional join: settings ride along as the
        // pre-injection for the fallback — with an outer session they are
        // ignored and the body joins it, without one they open a new session.
        // Callers cannot know at authoring time which side they will land on.
        if settings.shareSession, AgentSession.current != nil {
            return try await body()
        }

        let agent = try Self.agent(from: settings)
        let handle = try executor.openSession(provider: agent.provider)
        let session = AgentSession(handle: handle, agent: agent)

        return try await AgentSession.$current.withValue(session) {
            try await body()
        }
    }

    func send(prompt: String) async throws -> String {
        guard let session = AgentSession.current else {
            throw AgentSessionMissing(
                "agent step has no active agent session — run it inside an `invoke`'s"
                    + " steps (directly, or via dispatch from within one)"
            )
        }

        return try await LogContext.childNode {
            let invocation = AgentInvocation(
                id: UUID().uuidString,
                agent: session.agent,
                prompt: prompt,
                session: session.handle
            )

            return try await executor.run(invocation).text
        }
    }

    // MARK: - Private
    private static func agent(from settings: AgentSessionSettings) throws -> Agent {
        let permissionMode: PermissionMode?

        if let raw = settings.permissionMode {
            guard let mode = PermissionMode(rawValue: raw) else {
                throw AgentValidationError(
                    "invoke: permission_mode must be one of bypass/safe/restrict, got \(raw)"
                )
            }

            permissionMode = mode
        } else {
            permissionMode = nil
        }

        let environment = SubprocessEnv.merge(
            baseline: SubprocessEnv.baseline(accessToken: WorkflowExecutionState.accessToken),
            specOverride: settings.envExtra
        ) ?? [:]

        return try Agent(
            model: settings.model ?? "",
            allowed: try settings.allowed?.map { item in try AgentToolReference.decode(ValueBridge.json(item)) },
            workingDirectory: settings.cwd,
            environment: environment,
            permissionMode: permissionMode
        )
    }
}
