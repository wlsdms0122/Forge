//
//  AbortAction.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// The language's `throw` — the author ends the flow here with a reason. Like a
// thrown error it is catchable: a rescue on the aborting step (or a caller that
// treats the failure) may absorb it; unhandled, the run fails with the message.
public struct AbortAction: Action {
    // MARK: - Property
    public static let key = "abort"

    public let message: Reference

    public var referencedPaths: [[PathSegment]] { message.referencedPaths }

    // MARK: - Initializer
    public init(message: Reference) {
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        self.message = try Reference(from: decoder)
    }

    // MARK: - Public
    public func run(_ context: ActionContext) async throws -> Value {
        throw Aborted(try context.resolver.string(message))
    }

    public func encode(to encoder: Encoder) throws {
        try message.encode(to: encoder)
    }

    // MARK: - Private
}
