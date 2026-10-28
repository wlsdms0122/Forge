//
//  ServiceAckMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ServiceAckMethod: Sendable {
    // MARK: - Property
    let serviceBus: ServiceBus

    // MARK: - Initializer
    init(serviceBus: ServiceBus) {
        self.serviceBus = serviceBus
    }

    // MARK: - Public
    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONValue {
        guard let service = request.params["service"]?.stringValue, !service.isEmpty else {
            throw ProtocolError("service.ack: 'service' required")
        }

        try ServiceAuthorization.requireActingAs(
            service,
            claims: claims,
            method: "service.ack"
        )

        guard let messageID = request.params["message_id"]?.stringValue, !messageID.isEmpty else {
            throw ProtocolError("service.ack: 'message_id' required")
        }

        if let errorObject = request.params["error"]?.objectValue {
            let message = errorObject["message"]?.stringValue ?? "service error"
            await serviceBus.deliverError(
                service: service,
                messageID: messageID,
                message: message
            )
        } else {
            let result = request.params["result"]?.objectValue ?? [:]
            await serviceBus.deliverResult(
                service: service,
                messageID: messageID,
                result: .object(result)
            )
        }

        return ["ok": true]
    }

    // MARK: - Private
}
