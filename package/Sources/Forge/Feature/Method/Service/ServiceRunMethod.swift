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
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        let claims = try tokenAuthority.requireOperatorClaims(
            request.params,
            method: "service.run"
        )

        guard let name = request.params["name"] as? String, !name.isEmpty else {
            throw ProtocolError("service.run: 'name' (string) required")
        }

        try ServiceAuthz.requireActingAs(name, claims: claims, method: "service.run")

        let record = try await supervisor.run(name)

        return JSONObject(record.dict)
    }

    // MARK: - Private
}
