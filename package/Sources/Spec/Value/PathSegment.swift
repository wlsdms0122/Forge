//
//  PathSegment.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// A reference path in the semantic model. Frontends parse their own surface
// syntax (`a.b[0]`, whatever else) into these segments — the runtime never
// re-parses text, so the surface grammar stays a frontend fact.
public enum PathSegment: Sendable, Equatable {
    case key(String)
    case index(Int)
    case indexRef([PathSegment])
}

public extension Array where Element == PathSegment {
    // The canonical textual form — diagnostics and encoding share one spelling.
    var rendered: String {
        var rendered = ""

        for segment in self {
            switch segment {
            case .key(let key):
                rendered += (rendered.isEmpty ? "" : ".") + key

            case .index(let index):
                rendered += "[\(index)]"

            case .indexRef(let indexPath):
                rendered += "[\(indexPath.rendered)]"
            }
        }

        return rendered
    }

    // The root name this path reads from — nil when the path doesn't start
    // with a name, which no scope can serve.
    var head: String? {
        guard case .key(let head)? = first else { return nil }

        return head
    }

    // An index segment may itself name a binding — `${items[${i}]}` references
    // both `items` and `i`. Static validation must see the nested path too, or
    // a typo'd index escapes to runtime.
    var expandingIndexReferences: [[PathSegment]] {
        var paths: [[PathSegment]] = [self]

        for segment in self {
            guard case .indexRef(let indexPath) = segment else { continue }

            paths += indexPath.expandingIndexReferences
        }

        return paths
    }
}
