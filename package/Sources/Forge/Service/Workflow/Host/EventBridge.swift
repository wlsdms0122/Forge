//
//  EventBridge.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// Publishes forge's steps on its event stream. A step is a call of a verb
// that acts outside the program, from its native's start to its return or
// throw, and each such native announces its own (`ForgeAction`). The step is
// named by the statement that called the verb, and its action is the verb;
// a native a workflow calls directly is its own verb. Run-level framing
// (started/completed/failed) stays with whoever drives the executor.
struct EventBridge: Sendable {
    // MARK: - Property
    let workflowID: String
    let workflowName: String
    let verbs: Set<Name>
    let publish: @Sendable (WorkflowEvent) async -> Void

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

    // MARK: - Public
    // The step of the verb this native runs for, around what `body` does.
    func step<P: NativeProcedure>(
        of invocation: Warp.Invocation<P>,
        _ body: () async throws -> Warp.Value
    ) async throws -> Warp.Value {
        let call = invocation.trace.call(sentFrom: verbs)
        let step = call.statement.step

        await publish(WorkflowEvent(
            kind: .stepStarted,
            workflowID: workflowID,
            workflowName: workflowName,
            stepID: step,
            action: (call.verb ?? invocation.selector).spelling
        ))

        do {
            let result = try await body()

            await publish(WorkflowEvent(
                kind: .stepCompleted,
                workflowID: workflowID,
                workflowName: workflowName,
                stepID: step,
                output: ValueBridge.json(result)
            ))

            return result
        } catch {
            await publish(WorkflowEvent(
                kind: .stepFailed,
                workflowID: workflowID,
                workflowName: workflowName,
                stepID: step,
                errorType: String(describing: type(of: error)),
                errorMessage: "\(error)"
            ))

            throw error
        }
    }

    // MARK: - Private
}
