//
//  StreamUsage.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct StreamUsage: Sendable, Equatable {
    // MARK: - Property
    var inputTokens: Int?
    var outputTokens: Int?
    var cacheCreationInputTokens: Int?
    var cacheReadInputTokens: Int?

    // Claude counts `input_tokens` apart from the cache it reads and writes.
    var agentUsage: AgentUsage {
        AgentUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheWriteTokens: cacheCreationInputTokens,
            cacheReadTokens: cacheReadInputTokens
        )
    }

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
