//
//  WorkflowRunResult.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// The daemon-side vocabulary of a run — result, session and dispatch mode.
// These outlive the engine that first defined them.
struct WorkflowRunResult: Sendable {
    enum Status: String, Sendable {
        case ok
        case failed
    }

    struct RunFailure: Sendable {
        enum Kind: String, Sendable {
            case work
            case fault
            case cancelled
        }

        // MARK: - Property
        let kind: Kind
        let type: String
        let message: String

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let workflowID: String
    let workflowName: String
    let status: Status
    let outputs: [String: JSONValue]
    let durationMs: Int
    let error: RunFailure?

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
