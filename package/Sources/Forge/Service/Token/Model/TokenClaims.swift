//
//  TokenClaims.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct TokenClaims: Sendable, Codable {
    // MARK: - Property
    let principal: String
    let runID: String?
    let id: String

    // MARK: - Initializer
    init(principal: String, runID: String? = nil, id: String = UUID().uuidString) {
        self.principal = principal
        self.runID = runID
        self.id = id
    }

    // MARK: - Public
    // MARK: - Private
}
