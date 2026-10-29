//
//  StreamUsage.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct StreamUsage: Sendable, Equatable {
    // MARK: - Property
    var inputTokens: Int?
    var outputTokens: Int?
    var cacheCreationInputTokens: Int?
    var cacheReadInputTokens: Int?

    var asDictionary: [String: Int] {
        var values: [String: Int] = [:]

        if let inputTokens { values["input_tokens"] = inputTokens }
        if let outputTokens { values["output_tokens"] = outputTokens }

        if let cacheCreationInputTokens {
            values["cache_creation_input_tokens"] = cacheCreationInputTokens
        }

        if let cacheReadInputTokens {
            values["cache_read_input_tokens"] = cacheReadInputTokens
        }

        return values
    }

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
