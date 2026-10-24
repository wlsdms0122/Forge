//
//  WorkflowDispatchStreamMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct WorkflowDispatchStreamMethod: Sendable {
    // MARK: - Property
    let dispatchMethod: WorkflowDispatchMethod
    let eventBus: WorkflowEventBus

    // MARK: - Initializer
    init(dispatchMethod: WorkflowDispatchMethod, eventBus: WorkflowEventBus) {
        self.dispatchMethod = dispatchMethod
        self.eventBus = eventBus
    }

    // MARK: - Public
    func handle(
        _ request: RPCRequest,
        claims: TokenClaims,
        sink: any EventSink
    ) async throws {
        let prepared = try await dispatchMethod.prepare(request, claims: claims)

        try await DispatchAuthz.requireDispatch(
            principal: prepared.principal,
            workflow: prepared.workflow.name,
            policyStore: dispatchMethod.runner.policyStore,
            context: "dispatch"
        )

        let (token, stream) = await eventBus.subscribe()
        let expectedRoot = prepared.effectiveRootID

        await sink.emit(JSONObject([
            "id": request.id,
            "result": [
                "workflow_id": prepared.workflowID,
                "name":        prepared.workflow.name,
                "status":      "streaming",
            ] as [String: Any],
        ]))

        let dispatchMethodLocal = dispatchMethod
        let eventBusLocal = eventBus
        let runTask = Task<Result<WorkflowRunResult, Error>, Never> {
            let result: Result<WorkflowRunResult, Error>

            do {
                result = .success(
                    try await dispatchMethodLocal.runDispatch(prepared, mode: .awaited)
                )
            } catch {
                result = .failure(error)

                await Log.shared.append(
                    "dispatch.failed",
                    LogPayload([
                        "workflow":    prepared.workflow.name,
                        "workflow_id": prepared.workflowID,
                        "principal":   prepared.principal,
                        "error":       String(describing: error),
                    ]),
                    level: .error,
                    category: "workflow"
                )
            }

            await eventBusLocal.unsubscribe(token)

            return result
        }

        var awaited: Set<String> = [prepared.workflowID]
        var unawaited: Set<String> = []

        for await event in stream {
            guard event.rootID == expectedRoot else { continue }

            let id = event.workflowID

            if !awaited.contains(id) && !unawaited.contains(id) {
                guard let parent = event.parentRunID,
                    awaited.contains(parent) || unawaited.contains(parent)
                else {
                    continue
                }

                if event.asyncDispatch || unawaited.contains(parent) {
                    unawaited.insert(id)
                } else {
                    awaited.insert(id)
                }
            }

            var line = event.toJSONObject()
            line["kind"] = "workflow.event"

            if unawaited.contains(id) { line["unawaited"] = true }

            await sink.emit(JSONObject(line))
        }

        if Task.isCancelled { return }

        let resultObject: [String: Any]

        switch await runTask.value {
        case .success(let result):
            resultObject = dispatchMethod.encodeResult(result).dict

        case .failure(let error):
            resultObject = [
                "workflow_id": prepared.workflowID,
                "name":        prepared.workflow.name,
                "status":      "failed",
                "error":       ErrorObject(error).dict,
            ]
        }

        await sink.emit(JSONObject(["kind": "workflow.result", "result": resultObject]))
    }

    // MARK: - Private
}
