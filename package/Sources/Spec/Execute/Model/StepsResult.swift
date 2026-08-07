//
//  StepsResult.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// What running a step sequence produced — the scope with every binding, and the
// last executed step's output, which is a sequence's value when no explicit
// output is declared.
public struct StepsResult: Sendable {
    // MARK: - Property
    public let scope: Scope
    public let lastOutput: Value

    // MARK: - Initializer
    init(scope: Scope, lastOutput: Value) {
        self.scope = scope
        self.lastOutput = lastOutput
    }

    // MARK: - Public
    // MARK: - Private
}
