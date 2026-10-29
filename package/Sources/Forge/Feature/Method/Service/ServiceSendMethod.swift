//
//  ServiceSendMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ServiceSendMethod: Sendable {
    // MARK: - Property
    let serviceBus: ServiceBus
    let workRegistry: WorkRegistry

    // MARK: - Initializer
    init(
        serviceBus: ServiceBus,
        workRegistry: WorkRegistry
    ) {
        self.serviceBus = serviceBus
        self.workRegistry = workRegistry
    }

    // MARK: - Public
    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONValue {
        guard let service = request.params["service"]?.stringValue, !service.isEmpty else {
            throw ProtocolError("service.send: 'service' (string) required")
        }

        let payload = request.params["payload"]?.objectValue ?? [:]
        let isAsync = request.params["async"]?.boolValue ?? false
        let record = try await workRegistry.requireLiveRecord(
            runID: claims.runID,
            context: "service.send"
        )

        guard let handle = await serviceBus.handle(service: service) else {
            throw ProtocolError("service.send: no service '\(service)' is registered")
        }

        let envelope = MessageEnvelope(
            runID: record?.runID ?? "",
            origin:    record?.origin ?? .rpc,
            rootID:    record?.rootID,
            nodeID:     record?.nodeID,
            correlator: record?.correlator
        )

        return try await handle.send(
            envelope: envelope,
            payload: .object(payload),
            isAsync: isAsync
        )
    }

    // MARK: - Private
}
