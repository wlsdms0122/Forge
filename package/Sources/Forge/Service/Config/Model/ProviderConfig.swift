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
    let kind: String
    let settings: [String: String]

    // MARK: - Initializer
    init(name: String, kind: String, settings: [String: String]) {
        self.name = name
        self.kind = kind
        self.settings = settings
    }

    // MARK: - Public
    // MARK: - Private
}
