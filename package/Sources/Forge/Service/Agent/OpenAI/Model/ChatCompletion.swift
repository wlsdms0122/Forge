//
//  ChatCompletion.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ChatCompletion: Sendable, Equatable {
    // MARK: - Property
    let text: String
    let toolCalls: [ChatToolCall]
    let finishReason: ChatFinishReason
    let usage: AgentUsage?

    // MARK: - Initializer
    init(
        text: String,
        toolCalls: [ChatToolCall] = [],
        finishReason: ChatFinishReason = .unspecified,
        usage: AgentUsage? = nil
    ) {
        self.text = text
        self.toolCalls = toolCalls
        self.finishReason = finishReason
        self.usage = usage
    }

    // MARK: - Public
    // MARK: - Private
}
