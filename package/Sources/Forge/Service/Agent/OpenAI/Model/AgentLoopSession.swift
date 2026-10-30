//
//  AgentLoopSession.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

final class AgentLoopSession: BackendSession, @unchecked Sendable {
    // MARK: - Property
    var messages: [ChatMessage]

    // MARK: - Initializer
    init(messages: [ChatMessage] = []) {
        self.messages = messages
    }

    // MARK: - Public
    // MARK: - Private
}
