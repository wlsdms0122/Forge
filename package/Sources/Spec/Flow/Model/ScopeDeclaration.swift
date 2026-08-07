//
//  ScopeDeclaration.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public struct ScopeDeclaration: Sendable {
    // MARK: - Property
    public let label: String
    public let steps: [Step]

    // Whether the enclosing step id is bound inside this scope — loop and each
    // bind their round state; a branch arm or group binds nothing. The validator
    // grants visibility from this declaration, not from assumption.
    public let bindsOwnID: Bool

    // References the action resolves in the sub scope after its steps ran —
    // arm/loop outputs. Declared so validation can see them where they evaluate.
    public let trailingPaths: [[PathSegment]]

    // MARK: - Initializer
    public init(
        label: String,
        steps: [Step],
        bindsOwnID: Bool = false,
        trailingPaths: [[PathSegment]] = []
    ) {
        self.label = label
        self.steps = steps
        self.bindsOwnID = bindsOwnID
        self.trailingPaths = trailingPaths
    }

    // MARK: - Public
    // MARK: - Private
}
