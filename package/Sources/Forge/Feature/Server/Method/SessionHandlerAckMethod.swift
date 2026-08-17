//
//  SessionHandlerAckMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

struct SessionHandlerAckMethod: Sendable {
    // MARK: - Property
    let handlerBus: WorkflowHandlerBus
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(handlerBus: WorkflowHandlerBus, tokenAuthority: TokenAuthority) {
        self.handlerBus = handlerBus
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        let claims = try tokenAuthority.requireOperatorClaims(
            request.params,
            method: "session.handler.ack"
        )

        guard let service = request.params["service"] as? String, !service.isEmpty else {
            throw ProtocolError("session.handler.ack: 'service' required")
        }

        try ServiceAuthz.requireActingAs(
            service,
            claims: claims,
            method: "session.handler.ack"
        )

        guard let messageID = request.params["message_id"] as? String, !messageID.isEmpty else {
            throw ProtocolError("session.handler.ack: 'message_id' required")
        }

        if let errorObject = request.params["error"] as? [String: Any] {
            let message = (errorObject["message"] as? String) ?? "handler error"
            await handlerBus.deliverError(
                service: service,
                messageID: messageID,
                message: message
            )
        } else {
            let result = (request.params["result"] as? [String: Any]) ?? [:]
            await handlerBus.deliverResult(
                service: service,
                messageID: messageID,
                result: JSONObject(result)
            )
        }

        return ["ok": true]
    }

    // MARK: - Private
}
