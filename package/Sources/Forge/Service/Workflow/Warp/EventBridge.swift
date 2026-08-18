//
//  EventBridge.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp
import WarpIR

// Adapts the kernel's execution observations to forge's event stream. The
// kernel reports statements; run-level framing (started/completed/failed) stays
// with whoever drives the executor.
//
// Two of forge's event fields have no counterpart in the language any more and
// are reconstructed here: `absorbed` from the rescue the kernel announced, and
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

    // MARK: - Public
    func statementStarted(id: String, expression: Warp.Expression) async {
        await publish(WorkflowEvent(
            kind: .stepStarted,
            workflowID: workflowID,
            workflowName: workflowName,
            stepID: id,
            action: name(of: expression)
        ))
    }

    func statementCompleted(id: String, result: Warp.Value) async {
        await publish(WorkflowEvent(
            kind: .stepCompleted,
            workflowID: workflowID,
            workflowName: workflowName,
            stepID: id,
            output: ValueBridge.json(result),
            absorbed: await rescued.absorbed(id)
        ))
    }

    // A rescued failure never reaches `statementFailed` — the attempt swallowed
    // it — so the ledger's record of it is published from here, and the
    // completion that follows reports itself as absorbed.
    func failureRescued(name: String, error: any Error) async {
        await rescued.record(name)
        await publish(WorkflowEvent(
            kind: .stepFailed,
            workflowID: workflowID,
            workflowName: workflowName,
            stepID: name,
            errorType: String(describing: type(of: error)),
            errorMessage: "\(error)"
        ))
    }

    func statementFailed(id: String, error: any Error) async {
        await publish(WorkflowEvent(
            kind: .stepFailed,
            workflowID: workflowID,
            workflowName: workflowName,
            stepID: id,
            errorType: String(describing: type(of: error)),
            errorMessage: "\(error)"
        ))
    }

    // MARK: - Private
    private func name(of expression: Warp.Expression) -> String {
        switch expression {
        // `when:` is still a modifier in forge's notation, so it wraps the
        // construct the author actually wrote. The ledger names that one.
        case .conditional(_, let then, let otherwise) where otherwise == nil:
            return then.result.map { result in name(of: result) } ?? "branch"

        // A selector names itself, so nothing has to pair a step back to a
        // Swift type. What it names is the *linked* symbol — `forge.shell`, not
        // the `shell` an author typed — because that is what ran, and two
        // modules may spell a word the same way.
        case .dispatch(let dispatch):
            return dispatch.selector

        case .block:
            return "group"

        case .conditional:
            return "branch"

        case .loop:
            return "loop"

        case .iteration:
            return "each"

        case .concurrent:
            return "parallel"

        case .attempt:
            return "attempt"

        case .fail:
            return "abort"

        default:
            return "value"
        }
    }
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
