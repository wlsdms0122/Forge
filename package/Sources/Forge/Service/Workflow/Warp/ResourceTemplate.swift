//
//  ResourceTemplate.swift
//  Forge
//
//  Created by JSilver on 10/22/26.
//

import Foundation
import Warp

// A resource body read as a template: `${name}` stands for the input of that
// name in the language's spelling of it, null as `null` the way `format`
// writes it, and `$${` writes `${`. A name the inputs do not hold is refused.
struct ResourceTemplate {
    // MARK: - Property
    let body: String

    // MARK: - Initializer
    init(_ body: String) {
        self.body = body
    }

    // MARK: - Public
    func rendered(over inputs: [String: Value]) throws -> String {
        var rendered = ""
        var rest = body[...]

        while let open = rest.range(of: "${") {
            let before = rest[..<open.lowerBound]

            if before.hasSuffix("$") {
                rendered += before.dropLast() + "${"
                rest = rest[open.upperBound...]
                continue
            }

            rendered += before

            guard let close = rest[open.upperBound...].firstIndex(of: "}") else {
                throw ExecutionError("resource template: '${' is never closed")
            }

            let name = String(rest[open.upperBound..<close])

            guard let value = inputs[name] else {
                throw ExecutionError("resource template reads '\(name)', and no input of that name was handed")
            }

            rendered += ValueBridge.text(value)
            rest = rest[rest.index(after: close)...]
        }

        return rendered + rest
    }

    // MARK: - Private
}
