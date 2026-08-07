//
//  EventBridge.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

// Adapts the kernel's execution observations to forge's event stream. The
// kernel reports steps; run-level framing (started/completed/failed) stays with
// whoever drives the executor.
struct EventBridge: ExecutionObserver {
    // MARK: - Property
    let workflowID: String
    let workflowName: String
    let publish: @Sendable (WorkflowEvent) async -> Void

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
    func stepStarted(id: String, action: String) async {
        await publish(WorkflowEvent(
            kind: .stepStarted,
            workflowID: workflowID,
            workflowName: workflowName,
            stepID: id,
            action: action
        ))
    }

    func stepSkipped(id: String) async {
        await publish(WorkflowEvent(
            kind: .stepSkipped,
            workflowID: workflowID,
            workflowName: workflowName,
            stepID: id
        ))
    }

    func stepCompleted(id: String, output: Spec.Value, rescued: Bool) async {
        await publish(WorkflowEvent(
            kind: .stepCompleted,
            workflowID: workflowID,
            workflowName: workflowName,
            stepID: id,
            output: ValueBridge.json(output),
            absorbed: rescued
        ))
    }

    func stepFailed(id: String, error: any Error) async {
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
}
