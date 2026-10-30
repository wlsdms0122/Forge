//
//  ServiceRestartMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ServiceRestartMethod: Sendable {
    // MARK: - Property
    let supervisor: ServiceSupervisor

    // MARK: - Initializer
    // MARK: - Public
    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONValue {
        guard let name = request.params["name"]?.stringValue, !name.isEmpty else {
            throw ProtocolError("service.restart: 'name' (string) required")
        }

        try ServiceAuthorization.requireActingAs(name, claims: claims, method: "service.restart")

        let record = try await supervisor.restart(name)

        return .object(record.fields)
    }

    // MARK: - Private
}
