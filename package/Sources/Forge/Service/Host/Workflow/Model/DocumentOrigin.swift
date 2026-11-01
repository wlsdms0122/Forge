//
//  DocumentOrigin.swift
//  Forge
//
//  Created by JSilver on 10/26/26.
//

import Foundation
import Warp
import WarpSyntax
import WarpYAML

// A document Forge loaded from a workflow file: the identity a refusal's
// place names it by, and the `Origin` of the text it was spent from.
struct DocumentOrigin: Sendable {
    // MARK: - Property
    let identity: Identity
    let origin: Origin

    // MARK: - Initializer
    init(identity: Identity, origin: Origin) {
        self.identity = identity
        self.origin = origin
    }

    // MARK: - Public
    // A refusal as the author of the text reads it. A load's or a build's
    // whose place is in this document stands at the line and column the
    // place reaches in the text, marked nearest where the text did not write
    // that spot itself. Any other refusal says what it says.
    func described(_ refusal: any Error) -> String {
        guard
            let refused = refusal as? any WarpError,
            case let .array(place)? = refused.place?.value,
            place.count == 2,
            case let .bytes(bytes) = place[0],
            Identity(bytes) == identity,
            case let .array(steps) = place[1],
            let walked = Self.steps(steps)
        else {
            return "\(refusal)"
        }

        let reading = origin.reading(walked)

        return "\(reading.position)\(reading.exact ? "" : " (nearest)"): \(refused.message)"
    }

    // MARK: - Private
    // A place's steps as the text's origin walks them: a key the document
    // writes, a string, and a position in a list, an int.
    private static func steps(_ steps: [Value]) -> [Origin.Step]? {
        var walked: [Origin.Step] = []

        for step in steps {
            switch step {
            case let .string(key): walked.append(.key(key))
            case let .int(position): walked.append(.index(position))
            default: return nil
            }
        }

        return walked
    }
}
