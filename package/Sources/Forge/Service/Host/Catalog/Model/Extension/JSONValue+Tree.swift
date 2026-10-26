//
//  JSONValue+Tree.swift
//  Forge
//
//  Created by JSilver on 10/26/26.
//

import Foundation
import WarpYAML

// A tree a workflow file writes, as the wire carries it: a default a
// caller is told an omitted argument becomes.
extension JSONValue {
    init(_ tree: Tree) {
        switch tree.content {
        case .null:
            self = .null

        case let .bool(value):
            self = .bool(value)

        case let .int(value):
            self = .int(value)

        case let .double(value):
            self = .double(value)

        case let .string(value):
            self = .string(value)

        case let .array(elements):
            self = .array(elements.map(JSONValue.init))

        case let .dictionary(entries):
            self = .object(entries.mapValues(JSONValue.init))
        }
    }
}
