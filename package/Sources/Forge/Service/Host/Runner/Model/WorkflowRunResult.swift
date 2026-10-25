//
//  WorkflowRunResult.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// What a finished run answers: the value it returned or the failure it ended
// in, and its duration.
struct WorkflowRunResult: Sendable {
    enum Outcome: Sendable {
        case returned(Warp.Value)
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

    // The result as the wire writes it, where the value leaves as JSON.
    var jsonValue: JSONValue {
        get throws {
            var object: [String: JSONValue] = [
                "run_id": .string(runID),
                "name": .string(workflowName),
                "duration_ms": .int(durationMs)
            ]

            switch outcome {
            case let .returned(value):
                object["status"] = "ok"
                object["output"] = try ValueBridge.json(value)

            case let .failed(failure):
                object["status"] = "failed"
                object["error"] = failure.object.jsonValue
            }

            return .object(object)
        }
    }

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
