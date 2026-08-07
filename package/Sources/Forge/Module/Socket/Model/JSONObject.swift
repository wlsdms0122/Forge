//
//  JSONObject.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct JSONObject: @unchecked Sendable, ExpressibleByDictionaryLiteral {
    // MARK: - Property
    let dict: [String: Any]

    // MARK: - Initializer
    init(_ dict: [String: Any]) {
        self.dict = dict
    }

    init(dictionaryLiteral elements: (String, Any)...) {
        var dict: [String: Any] = [:]

        for (key, value) in elements { dict[key] = value }

        self.dict = dict
    }

    // MARK: - Public
    // MARK: - Private
}
