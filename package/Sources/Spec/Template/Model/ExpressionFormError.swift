//
//  ExpressionFormError.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// A malformed expression form — thrown during Value→expression interpretation
// and wrapped into DecodingError at the Codable boundary.
public struct ExpressionFormError: SpecError {
    // MARK: - Property
    public let message: String

    // MARK: - Initializer
    public init(_ message: String) {
        self.message = message
    }

    // MARK: - Public
    // MARK: - Private
}
