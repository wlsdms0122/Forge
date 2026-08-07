//
//  InvocationResult.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct InvocationResult: Sendable, Equatable {
    // MARK: - Property
    let text: String
    let usage: AgentUsage?
    let toolEvents: [ToolEvent]
    let durationMs: Int

    // MARK: - Initializer
    init(
        text: String,
        usage: AgentUsage? = nil,
        toolEvents: [ToolEvent] = [],
        durationMs: Int
    ) {
        self.text = text
        self.usage = usage
        self.toolEvents = toolEvents
        self.durationMs = durationMs
    }

    // MARK: - Public
    // MARK: - Private
}
