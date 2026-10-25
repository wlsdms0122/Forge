//
//  ValuePreview.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// The text an event writes for a value beside the value: its JSON text, or a
// string's own text, cut to its first `limit` characters, and the length of
// the whole text.
struct ValuePreview: Equatable, Sendable {
    // MARK: - Property
    static let limit = 2000

    let text: String
    let length: Int

    // MARK: - Initializer
    init(_ value: JSONValue) {
        let whole: String

        if case let .string(string) = value {
            whole = string
        } else {
            let data = (try? JSONEncoder().encode(value)) ?? Data()

            whole = String(decoding: data, as: UTF8.self)
        }

        self.text = String(whole.prefix(Self.limit))
        self.length = whole.count
    }

    // MARK: - Public
    // MARK: - Private
}
