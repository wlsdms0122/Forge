//
//  AgentSession.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct AgentSession: Sendable {
    // MARK: - Property
    // The session the agent turns of the current task speak through.
    @TaskLocal static var current: AgentSession?

    let handle: any BackendSession
    let agent: Agent

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
