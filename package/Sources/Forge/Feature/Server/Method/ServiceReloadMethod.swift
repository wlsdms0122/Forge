//
//  ServiceReloadMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ServiceReloadMethod: Sendable {
    // MARK: - Property
    let supervisor: ServiceSupervisor
    let tokenAuthority: TokenAuthority
    let configPath: String?
    let sessionHome: URL
    let configSnapshot: ConfigSnapshot

    // MARK: - Initializer
    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        let claims = try tokenAuthority.requireOperatorClaims(
            request.params,
            method: "service.reload"
        )

        try ServiceAuthz.requireGlobal(claims: claims, method: "service.reload")

        let (config, report) = try ConfigLoader.loadResolved(
            configPath: configPath,
            sessionHome: sessionHome
        )
        let diff = await supervisor.reload(config.services)

        await configSnapshot.updateServices(from: report)

        var result: [String: Any] = ["reloaded": true]

        for (key, value) in diff { result[key] = value }

        return JSONObject(result)
    }

    // MARK: - Private
}
