//
//  ProviderConfig.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ProviderConfig: Sendable, Equatable {
    // MARK: - Property
    let name: String
    let kind: BackendKind

    // MARK: - Initializer
    init(name: String, kind: BackendKind) {
        self.name = name
        self.kind = kind
    }
    
    init(
        name: String,
        kind: String?,
        settings: [String: String],
        apiKey: String?
    ) throws(ProviderDeclarationError) {
        let names = BackendKind.Name.allCases.map(\.rawValue).joined(separator: ", ")
        
        guard let kind else {
            throw ProviderDeclarationError("'kind' is required, one of \(names)")
        }
        
        guard let kindName = BackendKind.Name(rawValue: kind) else {
            throw ProviderDeclarationError("kind '\(kind)' is not one of \(names)")
        }
        
        self.name = name
        
        switch kindName {
        case .claudeCLI:
            self.kind = .claudeCLI(executable: settings["executable"] ?? "claude")
        
        case .codexCLI:
            self.kind = .codexCLI(executable: settings["executable"] ?? "codex")
        
        case .openAICompatible:
            guard let endpoint = settings["endpoint"].flatMap(URL.init(string:)) else {
                throw ProviderDeclarationError("\(kind) requires 'endpoint', the base URL")
            }
            
            self.kind = .openAICompatible(endpoint: endpoint, apiKey: apiKey)
        }
    }

    // MARK: - Public
    // MARK: - Private
}
