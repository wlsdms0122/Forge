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
    let executor: Executor

    // MARK: - Initializer
    init(executor: Executor) {
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
        if settings.shareSession, WorkflowExecutionState.agentSession != nil {
            return try await body()
        }

        let agent = try Self.agent(from: settings)
        let handle = try executor.openSession(provider: agent.provider)
        let session = AgentSession(handle: handle, agent: agent)

        return try await WorkflowExecutionState.$agentSession.withValue(session) {
            try await body()
        }
    }

    func send(prompt: String) async throws -> String {
        guard let session = WorkflowExecutionState.agentSession else {
            throw ProtocolError(
                "agent step has no active agent session — run it inside an `invoke`'s"
                    + " steps (directly, or via dispatch from within one)"
            )
        }

        return try await LogContext.childNode {
            let invocation = Invocation(
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
                throw ProtocolError(
                    "invoke: permission_mode must be one of bypass/safe/restrict, got \(raw)"
                )
            }

            permissionMode = mode
        } else {
            permissionMode = nil
        }

        let environment = SubprocessEnv.merge(
            baseline: SubprocessEnv.baseline(),
            specOverride: settings.envExtra
        ) ?? [:]

        return try Agent(
            model: settings.model ?? "",
            allowed: try Self.tools(from: settings.allowed),
            workingDirectory: settings.cwd,
            environment: environment,
            permissionMode: permissionMode
        )
    }

    private static func tools(from allowed: Warp.Value?) throws -> [AgentTool]? {
        guard let allowed else { return nil }

        switch allowed {
        case .null:
            return nil

        case .array(let items):
            return try items.map { item in try AgentToolReference.decode(ValueBridge.json(item)) }

        case let other:
            throw ProtocolError("invoke: tool list must resolve to an array, got \(other)")
        }
    }
}
