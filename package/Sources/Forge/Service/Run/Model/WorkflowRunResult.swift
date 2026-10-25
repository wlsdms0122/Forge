//
//  WorkflowRunResult.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// What a finished run answers: the value it returned or the failure it ended
// in, and its duration.
struct WorkflowRunResult: Sendable {
    enum Outcome: Sendable {
        case returned(JSONValue)
        case failed(RunFailure)
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
    let outcome: Outcome
    let durationMs: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
