//
//  EventBridge.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// Publishes forge's steps on its event stream. A step is a call of a verb
// that reaches outside the program, from its native's start to its return or
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
        of invocation: Invocation<P>,
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
                errorType: ErrorObject(failure: error).type,
                errorMessage: "\(Self.traced(error, at: invocation.trace))"
            ))

            throw error
        }
    }

    // MARK: - Private
    // The failure with the trace of the statement that called the native,
    // where it is a refusal that carries no trace of its own: the rounds of
    // a loop and the pieces of a fan-out share one step and differ there.
    private static func traced(_ error: any Error, at trace: Trace) -> any Error {
        guard let refused = error as? any WarpError, refused.trace == nil else { return error }

        return refused.tracing(trace)
    }
}
