//
//  CodexAgentConfiguration.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct CodexAgentConfiguration: Sendable {
    // MARK: - Property
    let model: String?
    let workingDirectory: String?
    let environment: [String: String]
    let permissionArguments: [String]
    let configurationArguments: [String]

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
