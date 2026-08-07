//
//  BackendFactory.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum BackendFactory {
    // MARK: - Property
    static let knownKinds = ["claude-cli", "codex-cli", "openai-compat"]
    
    // MARK: - Initializer
    // MARK: - Public
    static func make(_ provider: ProviderConfig) -> (any Backend)? {
        switch provider.kind {
        case "claude-cli":
            return ClaudeBackend(executable: provider.settings["executable"] ?? "claude")
        
        case "codex-cli":
            return CodexBackend(executable: provider.settings["executable"] ?? "codex")
        
        case "openai-compat":
            guard let endpoint = provider.settings["endpoint"],
                let url = URL(string: endpoint)
            else {
                return nil
            }
            
            let transport = OpenAICompatibleBackend(
                baseURL: url,
                apiKey: provider.settings["api_key"]
            )
            
            return AgentLoopBackend(transport: transport)
        
        default:
            return nil
        }
    }
    
    // MARK: - Private
}
