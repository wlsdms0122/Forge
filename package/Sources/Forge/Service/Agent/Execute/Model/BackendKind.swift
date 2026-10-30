//
//  BackendKind.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

package enum BackendKind: Sendable, Equatable {
    // The spelling a provider's `kind` takes in `config.toml`.
    package enum Name: String, CaseIterable, Sendable {
        case claudeCLI = "claude-cli"
        case codexCLI = "codex-cli"
        case openAICompatible = "openai-compat"
    }
    
    case claudeCLI(executable: String)
    case codexCLI(executable: String)
    case openAICompatible(endpoint: URL, apiKey: String?)
    
    // MARK: - Property
    var name: Name {
        switch self {
        case .claudeCLI:
            return .claudeCLI
        
        case .codexCLI:
            return .codexCLI
        
        case .openAICompatible:
            return .openAICompatible
        }
    }
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
