//
//  AgentTranslation.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct AgentTranslation<Value: Sendable>: Sendable {
    // MARK: - Property
    let value: Value
    let diagnostics: [AgentTranslationDiagnostic]

    // MARK: - Initializer
    init(_ value: Value, diagnostics: [AgentTranslationDiagnostic] = []) {
        self.value = value
        self.diagnostics = diagnostics
    }

    // MARK: - Public
    // MARK: - Private
}
