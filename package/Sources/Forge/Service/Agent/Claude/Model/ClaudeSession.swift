//
//  ClaudeSession.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

final class ClaudeSession: BackendSession, @unchecked Sendable {
    // MARK: - Property
    let sessionID: String

    var turnIndex: Int
    var established: Bool

    // MARK: - Initializer
    init(sessionID: String, turnIndex: Int = 0, established: Bool = false) {
        self.sessionID = sessionID
        self.turnIndex = turnIndex
        self.established = established
    }

    // MARK: - Public
    // MARK: - Private
}
