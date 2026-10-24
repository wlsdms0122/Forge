//
//  Invocation.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct Invocation: Sendable, Equatable {
    // MARK: - Property
    let id: String
    let agent: Agent
    let prompt: String
    let session: (any BackendSession)?
    let executionContext: AgentInvocationContext

    // MARK: - Initializer
    init(
        id: String,
        agent: Agent,
        prompt: String,
        session: (any BackendSession)? = nil,
        executionContext: AgentInvocationContext = AgentInvocationContext()
    ) {
        self.id = id
        self.agent = agent
        self.prompt = prompt
        self.session = session
        self.executionContext = executionContext
    }

    // MARK: - Public
    static func == (left: Invocation, right: Invocation) -> Bool {
        left.id == right.id && left.agent == right.agent && left.prompt == right.prompt
    }

    // MARK: - Private
}
