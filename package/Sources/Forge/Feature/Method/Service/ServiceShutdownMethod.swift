//
//  ServiceShutdownMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ServiceShutdownMethod: Sendable {
    // MARK: - Property
    let supervisor: ServiceSupervisor

    // MARK: - Initializer
    // MARK: - Public
    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONValue {
        guard let name = request.params["name"]?.stringValue, !name.isEmpty else {
            throw ProtocolError("service.shutdown: 'name' (string) required")
        }

        try ServiceAuthorization.requireActingAs(name, claims: claims, method: "service.shutdown")

        let record = try await supervisor.shutdown(name)

        return .object(record.fields)
    }

    // MARK: - Private
}
