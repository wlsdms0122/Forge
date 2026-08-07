//
//  Action.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// An action is a function the language calls by key. The kernel ships control-flow
// actions (value / branch / loop / each / use); hosts register their own leaves
// (shell, agent, ...) the same way — the language does not distinguish the two.
public protocol Action: Sendable, Codable {
    static var key: String { get }

    var scopeDeclarations: [ScopeDeclaration] { get }
    var referencedPaths: [[PathSegment]] { get }

    // Whether the action binds its own step id before its payload evaluates —
    // loop does (`${<id>.index}` inside `where`); most actions do not. The
    // validator reads this instead of assuming.
    var referencesOwnID: Bool { get }

    func run(_ context: ActionContext) async throws -> Value
}

public extension Action {
    var scopeDeclarations: [ScopeDeclaration] { [] }

    var referencedPaths: [[PathSegment]] { [] }

    var referencesOwnID: Bool { false }
}
