//
//  BackendFactory.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum BackendFactory {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func make(_ configuration: BackendConfiguration) -> any Backend {
        switch configuration {
        case let .claudeCLI(executable):
            return ClaudeBackend(executable: executable)
        
        case let .codexCLI(executable):
            return CodexBackend(executable: executable)
        
        case let .openAICompatible(endpoint, apiKey):
            return AgentLoopBackend(
                transport: OpenAICompatibleTransport(baseURL: endpoint, apiKey: apiKey)
            )
        }
    }
    
    // MARK: - Private
}
