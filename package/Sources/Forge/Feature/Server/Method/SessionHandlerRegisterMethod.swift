//
//  SessionHandlerRegisterMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

struct SessionHandlerRegisterMethod: Sendable {
    // MARK: - Property
    let handlerBus: WorkflowHandlerBus
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(handlerBus: WorkflowHandlerBus, tokenAuthority: TokenAuthority) {
        self.handlerBus = handlerBus
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    func handle(_ request: RPCRequest, sink: any EventSink) async throws {
        let claims = try tokenAuthority.requireOperatorClaims(
            request.params,
            method: "session.handler.register"
        )

        guard let service = request.params["service"] as? String, !service.isEmpty else {
            throw ProtocolError("session.handler.register: 'service' (string) required")
        }

        try ServiceAuthz.requireActingAs(
            service,
            claims: claims,
            method: "session.handler.register"
        )

        let schemaObject = request.params["schema"] as? [String: Any]
        let schema = schemaObject.map { object in JSONObject(object) }
        let handle = await handlerBus.register(service: service, schema: schema, sink: sink)

        await sink.emit(JSONObject([
            "id":     request.id,
            "result": ["registered": true, "service": service],
        ]))

        do {
            try await Task.sleep(for: .seconds(1_000_000_000))
        } catch {
        }

        await handlerBus.unregister(service: service, handle: handle)
    }

    // MARK: - Private
}
