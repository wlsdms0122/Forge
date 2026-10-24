//
//  EventBridge.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// Adapts the language's execution observations to forge's event stream. A
// step is a statement that calls one of forge's verbs, and its action is the
// verb's name; every other statement a run performs is the workflow's own
// working and is no step. Run-level framing (started/completed/failed) stays
// with whoever drives the executor.
struct EventBridge: ExecutionObserver {
    // MARK: - Property
    let workflowID: String
    let workflowName: String
    let verbs: Set<Name>
    let publish: @Sendable (WorkflowEvent) async -> Void

    private let steps = StartedSteps()

    // MARK: - Initializer
    init(
        workflowID: String,
        workflowName: String,
        verbs: Set<Name>,
        publish: @escaping @Sendable (WorkflowEvent) async -> Void
    ) {
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.verbs = verbs
        self.publish = publish
    }

    // MARK: - Lifecycle
    func statementStarted(at trace: Trace, construct: Construct, callee: Name?) async {
        guard let callee, verbs.contains(callee) else { return }

        await steps.start(trace)
        await publish(WorkflowEvent(
            kind: .stepStarted,
            workflowID: workflowID,
            workflowName: workflowName,
            stepID: trace.step,
            action: callee.spelling
        ))
    }

    func statementCompleted(at trace: Trace, result: Warp.Value) async {
        guard await steps.end(trace) else { return }

        await publish(WorkflowEvent(
            kind: .stepCompleted,
            workflowID: workflowID,
            workflowName: workflowName,
            stepID: trace.step,
            output: ValueBridge.json(result)
        ))
    }

    func statementFailed(at trace: Trace, error: any Error) async {
        guard await steps.end(trace) else { return }

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

// The steps that started and have not ended, each by the occurrence its trace
// names, since pieces of a fan-out and rounds of a loop run one statement many
// times.
private actor StartedSteps {
    // MARK: - Property
    private var occurrences: Set<String> = []

    // MARK: - Initializer
    // MARK: - Public
    func start(_ trace: Trace) {
        occurrences.insert(trace.rendered)
    }

    func end(_ trace: Trace) -> Bool {
        occurrences.remove(trace.rendered) != nil
    }

    // MARK: - Private
}
