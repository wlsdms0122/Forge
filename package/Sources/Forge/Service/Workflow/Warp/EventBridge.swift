//
//  EventBridge.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// Adapts the language's execution observations to forge's event stream. Warp
// reports statements; run-level framing (started/completed/failed) stays
// with whoever drives the executor.
//
// Two of forge's event fields have no counterpart in the language any more and
// are reconstructed here: `absorbed` from the rescue the language announced, and
// the step's word from the shape of the expression. Both belong to forge's
// surface, which is why they are computed on this side of the seam.
struct EventBridge: ExecutionObserver {
    // MARK: - Property
    let workflowID: String
    let workflowName: String
    let publish: @Sendable (WorkflowEvent) async -> Void

    private let rescued = RescuedStatements()

    // MARK: - Initializer
    init(
        workflowID: String,
        workflowName: String,
        publish: @escaping @Sendable (WorkflowEvent) async -> Void
    ) {
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.publish = publish
    }

    // MARK: - Lifecycle
    func statementStarted(at trace: Trace) async {
        await publish(WorkflowEvent(
            kind: .stepStarted,
            workflowID: workflowID,
            workflowName: workflowName,
            stepID: trace.step
        ))
    }

    func statementCompleted(at trace: Trace, result: Warp.Value) async {
        await publish(WorkflowEvent(
            kind: .stepCompleted,
            workflowID: workflowID,
            workflowName: workflowName,
            stepID: trace.step,
            output: ValueBridge.json(result),
            absorbed: await rescued.absorbed(trace.step)
        ))
    }

    // A rescued failure never reaches `statementFailed`, so the ledger's record
    // of it is published from here, and the completion that follows reports
    // itself as absorbed.
    func failureRescued(name: String?, error: any Error) async {
        let step = name ?? ""

        await rescued.record(step)
        await publish(WorkflowEvent(
            kind: .stepFailed,
            workflowID: workflowID,
            workflowName: workflowName,
            stepID: step,
            errorType: String(describing: type(of: error)),
            errorMessage: "\(error)"
        ))
    }

    func statementFailed(at trace: Trace, error: any Error) async {
        await publish(WorkflowEvent(
            kind: .stepFailed,
            workflowID: workflowID,
            workflowName: workflowName,
            stepID: trace.step,
            errorType: String(describing: type(of: error)),
            errorMessage: "\(error)"
        ))
    }

    // MARK: - Public
    // MARK: - Private
}

private actor RescuedStatements {
    // MARK: - Property
    private var names: Set<String> = []

    // MARK: - Initializer
    // MARK: - Public
    func record(_ name: String) {
        names.insert(name)
    }

    func absorbed(_ name: String) -> Bool {
        names.contains(name)
    }

    // MARK: - Private
}
