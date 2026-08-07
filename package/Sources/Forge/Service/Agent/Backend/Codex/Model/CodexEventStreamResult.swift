//
//  CodexEventStreamResult.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct CodexEventStreamResult: Sendable, Equatable {
    // MARK: - Property
    var threadIdentifier: String?
    var finalText: String
    var toolEvents: [ToolEvent]
    var usage: AgentUsage?
    var failure: String?
    var sawThreadStarted: Bool
    var sawAgentMessage: Bool
    var sawTurnCompleted: Bool
    var malformedLineCount: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
