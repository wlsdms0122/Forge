//
//  ToolSpec.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ToolSpec: Sendable, Equatable {
    // MARK: - Property
    let name: String
    let description: String
    let parametersJSON: String

    // MARK: - Initializer
    init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }

    // MARK: - Public
    // MARK: - Private
}
