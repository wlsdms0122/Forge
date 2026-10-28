//
//  ServiceRegisterMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ServiceRegisterMethod: Sendable {
    // MARK: - Property
    let serviceBus: ServiceBus

    // MARK: - Initializer
    init(serviceBus: ServiceBus) {
        self.serviceBus = serviceBus
    }

    // MARK: - Public
    func handle(
        _ request: RPCRequest,
        claims: TokenClaims,
        sink: any EventSink
    ) async throws {
        guard let service = request.params["service"]?.stringValue, !service.isEmpty else {
            throw ProtocolError("service.register: 'service' (string) required")
        }

        try ServiceAuthorization.requireActingAs(
            service,
            claims: claims,
            method: "service.register"
        )

        let schema = request.params["schema"]?.objectValue.map(JSONValue.object)
        let handle = await serviceBus.register(service: service, schema: schema, sink: sink)

        await sink.emit([
            "id":     .string(request.id),
            "result": ["registered": true, "service": .string(service)]
        ])

        do {
            try await Task.sleep(for: .seconds(1_000_000_000))
        } catch {
        }

        await serviceBus.unregister(service: service, handle: handle)
    }

    // MARK: - Private
}
