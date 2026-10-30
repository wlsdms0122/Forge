//
//  CodexSession.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

final class CodexSession: BackendSession, @unchecked Sendable {
    // MARK: - Property
    var threadIdentifier: String?
    var turnIndex: Int
    var cumulativeUsage: AgentUsage?

    // MARK: - Initializer
    init(threadIdentifier: String? = nil, turnIndex: Int = 0) {
        self.threadIdentifier = threadIdentifier
        self.turnIndex = turnIndex
    }

    // MARK: - Public
    // MARK: - Private
}
