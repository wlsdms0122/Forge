//
//  ReferenceNotFound.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public struct ReferenceNotFound: RecoverableFailure {
    // MARK: - Property
    public let path: [PathSegment]

    public var message: String { "reference not found: { ref: \(path.rendered) }" }

    public var payload: Value {
        .object([
            "type": .string("reference_not_found"),
            "message": .string(message),
            "path": .string(path.rendered)
        ])
    }

    // MARK: - Initializer
    public init(path: [PathSegment]) {
        self.path = path
    }

    // MARK: - Public
    // MARK: - Private
}
