//
//  ServiceRunMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ServiceRunMethod: Sendable {
    // MARK: - Property
    let supervisor: ServiceSupervisor

    // MARK: - Initializer
    // MARK: - Public
    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONValue {
        guard let name = request.params["name"]?.stringValue, !name.isEmpty else {
            throw ProtocolError("service.run: 'name' (string) required")
        }

        try ServiceAuthz.requireActingAs(name, claims: claims, method: "service.run")

        let record = try await supervisor.run(name)

        return .object(record.fields)
    }

    // MARK: - Private
}
