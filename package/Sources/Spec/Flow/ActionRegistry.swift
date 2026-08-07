//
//  ActionRegistry.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public struct ActionRegistry: Sendable {
    // MARK: - Property
    // The built-in set is a compile-time constant with unique keys — a throw here
    // would be a kernel bug, so the forced try is the honest reaction.
    public static let standard = try! ActionRegistry(actions: [
        ValueAction.self,
        BranchAction.self,
        LoopAction.self,
        EachAction.self,
        ParallelAction.self,
        GroupAction.self,
        UseAction.self,
        AbortAction.self
    ])

    public var keys: [String] { actions.keys.sorted() }

    private var actions: [String: any Action.Type]

    // MARK: - Initializer
    public init(actions: [any Action.Type] = []) throws {
        self.actions = [:]

        for action in actions {
            try insert(action)
        }
    }

    // MARK: - Public
    public func registering(_ action: any Action.Type) throws -> ActionRegistry {
        var registry = self

        try registry.insert(action)

        return registry
    }

    public func actionType(for key: String) -> (any Action.Type)? {
        actions[key]
    }

    // MARK: - Private
    // A key is claimed once — silently replacing an action would let a host swap
    // out the language's own control structures without a trace.
    private mutating func insert(_ action: any Action.Type) throws {
        guard actions[action.key] == nil else {
            throw ValidationError(
                "action key '\(action.key)' is already registered"
            )
        }

        actions[action.key] = action
    }
}
