//
//  ValueAction.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

public struct ValueAction: Action {
    // MARK: - Property
    public static let key = "value"

    public let reference: Reference

    public var referencedPaths: [[PathSegment]] { reference.referencedPaths }

    // MARK: - Initializer
    public init(reference: Reference) {
        self.reference = reference
    }

    public init(from decoder: Decoder) throws {
        self.reference = try Reference(from: decoder)
    }

    // MARK: - Public
    public func run(_ context: ActionContext) async throws -> Value {
        try context.resolver.resolve(reference)
    }

    public func encode(to encoder: Encoder) throws {
        try reference.encode(to: encoder)
    }

    // MARK: - Private
}
