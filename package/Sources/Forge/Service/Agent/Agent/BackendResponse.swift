//
//  BackendResponse.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct BackendResponse: Sendable, Equatable {
    // MARK: - Property
    let text: String
    let modelReference: ModelReference?
    let usage: AgentUsage?
    let toolEvents: [ToolEvent]
    let stdoutLength: Int
    let durationMs: Int

    // MARK: - Initializer
    init(
        text: String,
        modelReference: ModelReference? = nil,
        usage: AgentUsage? = nil,
        toolEvents: [ToolEvent] = [],
        stdoutLength: Int = 0,
        durationMs: Int = 0
    ) {
        self.text = text
        self.modelReference = modelReference
        self.usage = usage
        self.toolEvents = toolEvents
        self.stdoutLength = stdoutLength
        self.durationMs = durationMs
    }

    // MARK: - Public
    // MARK: - Private
}
