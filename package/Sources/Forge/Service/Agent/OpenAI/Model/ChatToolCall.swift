//
//  ChatToolCall.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ChatToolCall: Sendable, Equatable {
    // MARK: - Property
    let id: String
    let name: String
    let arguments: String

    // MARK: - Initializer
    init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    // MARK: - Public
    // MARK: - Private
}
