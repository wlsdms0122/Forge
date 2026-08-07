//
//  OpenAICompatibleAgentConfiguration.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct OpenAICompatibleAgentConfiguration: Sendable {
    // MARK: - Property
    let model: String
    let workingDirectory: String?
    let environment: [String: String]?
    let commandAuthorization: CommandAuthorizationPolicy
    let tools: [ToolSpec]

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
