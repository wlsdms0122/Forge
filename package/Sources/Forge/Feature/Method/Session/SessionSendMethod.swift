//
//  SessionSendMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct SessionSendMethod: Sendable {
    // MARK: - Property
    let handlerBus: WorkflowHandlerBus
    let workRegistry: WorkRegistry

    // MARK: - Initializer
    init(
        handlerBus: WorkflowHandlerBus,
        workRegistry: WorkRegistry
    ) {
        self.handlerBus = handlerBus
        self.workRegistry = workRegistry
    }

    // MARK: - Public
    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONObject {
        guard let service = request.params["service"] as? String, !service.isEmpty else {
            throw ProtocolError("session.send: 'service' (string) required")
        }

        let payloadDict = (request.params["payload"] as? [String: Any]) ?? [:]
        let isAsync = (request.params["async"] as? Bool) ?? false
        let record = try await workRegistry.requireLiveRecord(
            workflowID: claims.workflowID,
            context: "session.send"
        )

        guard let handle = await handlerBus.handle(service: service) else {
            throw ProtocolError("session.send: no handler registered for service '\(service)'")
        }

        let envelope = HandlerFrameEnvelope(
            workflowID: record?.workflowID ?? "",
            origin:    record?.origin ?? .rpc,
            rootID:    record?.rootID,
            nodeID:     record?.nodeID,
            correlator: record?.correlator
        )

        return try await handle.send(
            envelope: envelope,
            payload: JSONObject(payloadDict),
            isAsync: isAsync
        )
    }

    // MARK: - Private
}
