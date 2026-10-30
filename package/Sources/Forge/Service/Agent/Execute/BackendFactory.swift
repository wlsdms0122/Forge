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
    static func make(_ provider: ProviderConfig) -> (any Backend)? {
        guard let kind = BackendKind(rawValue: provider.kind) else { return nil }
        
        switch kind {
        case .claudeCLI:
            return ClaudeBackend(executable: provider.settings["executable"] ?? "claude")
        
        case .codexCLI:
            return CodexBackend(executable: provider.settings["executable"] ?? "codex")
        
        case .openAICompatible:
            guard let endpoint = provider.settings["endpoint"],
                let url = URL(string: endpoint)
            else {
                return nil
            }
            
            let transport = OpenAICompatibleTransport(
                baseURL: url,
                apiKey: provider.settings["api_key"]
            )
            
            return AgentLoopBackend(transport: transport)
        }
    }
    
    // MARK: - Private
}
