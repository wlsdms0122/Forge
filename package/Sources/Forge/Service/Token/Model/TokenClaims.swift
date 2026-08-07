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
    let workflowID: String?
    let id: String

    // MARK: - Initializer
    init(principal: String, workflowID: String? = nil, id: String = UUID().uuidString) {
        self.principal = principal
        self.workflowID = workflowID
        self.id = id
    }

    // MARK: - Public
    // MARK: - Private
}
