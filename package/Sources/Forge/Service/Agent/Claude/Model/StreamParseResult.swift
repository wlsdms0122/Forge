//
//  StreamParseResult.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct StreamParseResult: Sendable, Equatable {
    // MARK: - Property
    var finalText: String
    var toolEvents: [ToolEvent]
    var usage: StreamUsage?
    var malformedLineCount: Int = 0
    var sawTerminalResult: Bool = false

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
