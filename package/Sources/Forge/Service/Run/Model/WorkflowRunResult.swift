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
    enum Status: String, Sendable {
        case ok
        case failed
    }

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

    var status: Status {
        switch outcome {
        case .returned:
            return .ok

        case .failed:
            return .failed
        }
    }

    // The value the run returned, which a run that failed has none of.
    var output: JSONValue? {
        guard case let .returned(value) = outcome else { return nil }

        return value
    }

    var error: RunFailure? {
        guard case let .failed(failure) = outcome else { return nil }

        return failure
    }

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
