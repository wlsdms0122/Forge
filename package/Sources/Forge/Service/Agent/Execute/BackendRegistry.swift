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
                throw BackendNotRegistered(
                    "a model names no provider, and \(byProvider.count) backends are registered"
                        + " (\(byProvider.keys.sorted().joined(separator: ", "))); name one as"
                        + " `<provider>[:<model>]`"
                )
            }
            
            return sole
        }
        
        guard let backend = byProvider[provider] else {
            throw BackendNotRegistered(
                "no backend registered for provider '\(provider)' (have: \(byProvider.keys.sorted().joined(separator: ", ")))"
            )
        }
        
        return backend
    }
    
    // MARK: - Private
}
