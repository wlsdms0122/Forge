//
//  HandlerRegisterMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct HandlerRegisterMethod: Sendable {
    // MARK: - Property
    let handlerBus: WorkflowHandlerBus

    // MARK: - Initializer
    init(handlerBus: WorkflowHandlerBus) {
        self.handlerBus = handlerBus
    }

    // MARK: - Public
    func handle(
        _ request: RPCRequest,
        claims: TokenClaims,
        sink: any EventSink
    ) async throws {
        guard let service = request.params["service"]?.stringValue, !service.isEmpty else {
            throw ProtocolError("handler.register: 'service' (string) required")
        }

        try ServiceAuthz.requireActingAs(
            service,
            claims: claims,
            method: "handler.register"
        )

        let schema = request.params["schema"]?.objectValue.map(JSONValue.object)
        let handle = await handlerBus.register(service: service, schema: schema, sink: sink)

        await sink.emit([
            "id":     .string(request.id),
            "result": ["registered": true, "service": .string(service)]
        ])

        do {
            try await Task.sleep(for: .seconds(1_000_000_000))
        } catch {
        }

        await handlerBus.unregister(service: service, handle: handle)
    }

    // MARK: - Private
}
