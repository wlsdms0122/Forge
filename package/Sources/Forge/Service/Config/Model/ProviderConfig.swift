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
    let backend: BackendConfiguration

    // MARK: - Initializer
    init(name: String, backend: BackendConfiguration) {
        self.name = name
        self.backend = backend
    }
    
    init(
        name: String,
        kind: String?,
        settings: [String: String],
        apiKey: String?
    ) throws(ProviderDeclarationError) {
        let names = BackendKind.allCases.map(\.rawValue).joined(separator: ", ")
        
        guard let kind else {
            throw ProviderDeclarationError("'kind' is required, one of \(names)")
        }
        
        guard let backendKind = BackendKind(rawValue: kind) else {
            throw ProviderDeclarationError("kind '\(kind)' is not one of \(names)")
        }
        
        let read: [String] = switch backendKind {
        case .claudeCLI, .codexCLI: ["executable"]
        case .openAICompatible: ["endpoint"]
        }
        let unknown = settings.keys.filter { key in !read.contains(key) }.sorted()
        
        guard unknown.isEmpty else {
            throw ProviderDeclarationError(
                "\(kind) does not read \(unknown.map { key in "'\(key)'" }.joined(separator: ", "))"
                    + "; it reads \(read.joined(separator: ", "))"
            )
        }
        
        self.name = name
        
        switch backendKind {
        case .claudeCLI:
            self.backend = .claudeCLI(executable: settings["executable"] ?? "claude")
        
        case .codexCLI:
            self.backend = .codexCLI(executable: settings["executable"] ?? "codex")
        
        case .openAICompatible:
            guard let endpoint = settings["endpoint"].flatMap(URL.init(string:)) else {
                throw ProviderDeclarationError("\(kind) requires 'endpoint', the base URL")
            }
            
            self.backend = .openAICompatible(endpoint: endpoint, apiKey: apiKey)
        }
    }

    // MARK: - Public
    // MARK: - Private
}
