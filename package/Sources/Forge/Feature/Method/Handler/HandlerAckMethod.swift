//
//  HandlerAckMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct HandlerAckMethod: Sendable {
    // MARK: - Property
    let handlerBus: WorkflowHandlerBus

    // MARK: - Initializer
    init(handlerBus: WorkflowHandlerBus) {
        self.handlerBus = handlerBus
    }

    // MARK: - Public
    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONValue {
        guard let service = request.params["service"]?.stringValue, !service.isEmpty else {
            throw ProtocolError("handler.ack: 'service' required")
        }

        try ServiceAuthz.requireActingAs(
            service,
            claims: claims,
            method: "handler.ack"
        )

        guard let messageID = request.params["message_id"]?.stringValue, !messageID.isEmpty else {
            throw ProtocolError("handler.ack: 'message_id' required")
        }

        if let errorObject = request.params["error"]?.objectValue {
            let message = errorObject["message"]?.stringValue ?? "handler error"
            await handlerBus.deliverError(
                service: service,
                messageID: messageID,
                message: message
            )
        } else {
            let result = request.params["result"]?.objectValue ?? [:]
            await handlerBus.deliverResult(
                service: service,
                messageID: messageID,
                result: .object(result)
            )
        }

        return ["ok": true]
    }

    // MARK: - Private
}
