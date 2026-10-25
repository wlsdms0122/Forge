//
//  WorkflowRunResult.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// What a finished run answers: its status, the value it returned (null for a
// run that failed), its duration and its failure.
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
        let object: ErrorObject

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let runID: String
    let workflowName: String
    let status: Status
    let outputs: JSONValue
    let durationMs: Int
    let error: RunFailure?

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
