//
//  ReferenceUnfit.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public struct ReferenceUnfit: SpecError {
    // MARK: - Property
    public let path: [PathSegment]
    public let reason: String

    public var message: String {
        "reference unfit: { ref: \(path.rendered) } — \(reason)"
    }

    // MARK: - Initializer
    public init(path: [PathSegment], reason: String) {
        self.path = path
        self.reason = reason
    }

    // MARK: - Public
    // MARK: - Private
}
