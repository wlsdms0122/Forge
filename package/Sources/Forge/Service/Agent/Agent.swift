//
//  Agent.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct Agent: Sendable, Equatable {
    // MARK: - Property
    let model: ModelReference
    let allowed: [AgentTool]?
    let workingDirectory: String?
    let environment: [String: String]
    let permissionMode: PermissionMode?

    var provider: String { model.provider }

    // MARK: - Initializer
    init(
        model: String,
        allowed: [AgentTool]? = nil,
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        permissionMode: PermissionMode? = nil
    ) throws {
        self.model = try ModelReference(model)
        self.allowed = allowed
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.permissionMode = permissionMode
    }

    // MARK: - Public
    // MARK: - Private
}
