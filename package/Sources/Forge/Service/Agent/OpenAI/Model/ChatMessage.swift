//
//  ChatMessage.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ChatMessage: Sendable, Equatable {
    enum Role: String, Sendable, Equatable {
        case system
        case user
        case assistant
        case tool
    }

    // MARK: - Property
    let role: Role
    let content: String
    let toolCalls: [ChatToolCall]
    let toolCallID: String?

    // MARK: - Initializer
    init(
        role: Role,
        content: String,
        toolCalls: [ChatToolCall] = [],
        toolCallID: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    // MARK: - Public
    // MARK: - Private
}
