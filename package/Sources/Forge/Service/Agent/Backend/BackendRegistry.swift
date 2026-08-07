//
//  BackendRegistry.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct BackendRegistry: Sendable {
    // MARK: - Property
    private let byProvider: [String: any Backend]
    
    // MARK: - Initializer
    init(_ byProvider: [String: any Backend]) {
        self.byProvider = byProvider
    }
    
    // MARK: - Public
    func resolve(provider: String?) throws -> any Backend {
        guard let provider else {
            guard byProvider.count == 1, let sole = byProvider.values.first else {
                throw ResolutionError(
                    "invoke: 'provider' is required — \(byProvider.count) backends registered (\(byProvider.keys.sorted())); forge picks no default"
                )
            }
            
            return sole
        }
        
        guard let backend = byProvider[provider] else {
            throw ResolutionError(
                "no backend registered for provider '\(provider)' (have: \(byProvider.keys.sorted()))"
            )
        }
        
        return backend
    }
    
    // MARK: - Private
}
