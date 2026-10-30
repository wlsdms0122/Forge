//
//  BackendConfiguration.swift
//  Forge
//
//  Created by JSilver on 10/30/26.
//

import Foundation

enum BackendConfiguration: Sendable, Equatable {
    case claudeCLI(executable: String)
    case codexCLI(executable: String)
    case openAICompatible(endpoint: URL, apiKey: String?)
    
    // MARK: - Property
    var kind: BackendKind {
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
