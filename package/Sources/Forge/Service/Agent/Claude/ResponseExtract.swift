//
//  ResponseExtract.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

enum ResponseExtract {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func text(_ raw: String) -> String {
        guard
            let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return raw
        }

        for key in ["result", "content", "text", "output"] {
            if let value = object[key] as? String { return value }

            if let values = object[key] as? [Any] {
                let parts: [String] = values.compactMap { element in
                    if
                        let dictionary = element as? [String: Any],
                        let text = dictionary["text"] as? String
                    {
                        return text
                    }

                    if let string = element as? String { return string }

                    return nil
                }

                if !parts.isEmpty { return parts.joined() }
            }
        }

        return raw
    }

    // MARK: - Private
}
