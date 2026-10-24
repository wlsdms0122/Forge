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
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        let claims = try tokenAuthority.requireOperatorClaims(
            request.params,
            method: "service.restart"
        )

        guard let name = request.params["name"] as? String, !name.isEmpty else {
            throw ProtocolError("service.restart: 'name' (string) required")
        }

        try ServiceAuthz.requireActingAs(name, claims: claims, method: "service.restart")

        let record = try await supervisor.restart(name)

        return JSONObject(record.dict)
    }

    // MARK: - Private
}
