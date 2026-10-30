//
//  ChatTransport.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

protocol ChatTransport: Sendable {
    func complete(
        messages: [ChatMessage],
        tools: [ToolSpec],
        model: String?,
        jsonMode: Bool
    ) async throws -> ChatCompletion
}
