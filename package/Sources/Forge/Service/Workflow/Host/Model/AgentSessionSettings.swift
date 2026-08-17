//
//  AgentSessionSettings.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

struct AgentSessionSettings: Sendable {
    // MARK: - Property
    let model: String?
    let allowed: Warp.Value?
    let cwd: String?
    let permissionMode: String?
    let envExtra: [String: String]
    let shareSession: Bool

    // MARK: - Initializer
    init(
        model: String? = nil,
        allowed: Warp.Value? = nil,
        cwd: String? = nil,
        permissionMode: String? = nil,
        envExtra: [String: String] = [:],
        shareSession: Bool = false
    ) {
        self.model = model
        self.allowed = allowed
        self.cwd = cwd
        self.permissionMode = permissionMode
        self.envExtra = envExtra
        self.shareSession = shareSession
    }

    // MARK: - Public
    // MARK: - Private
}
