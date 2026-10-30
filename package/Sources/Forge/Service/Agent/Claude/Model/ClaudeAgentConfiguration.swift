//
//  ClaudeAgentConfiguration.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ClaudeAgentConfiguration: Sendable, Equatable {
    // MARK: - Property
    let model: String?
    let workingDirectory: String?
    let environment: [String: String]
    let availableTools: [String]?
    let allowedTools: [String]?
    let permissionMode: String?

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
