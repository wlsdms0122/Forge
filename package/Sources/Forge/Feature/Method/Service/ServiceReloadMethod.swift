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
    let configPath: String?
    let instanceHome: URL
    let configSnapshot: ConfigSnapshot

    // MARK: - Initializer
    // MARK: - Public
    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONValue {
        try ServiceAuthorization.requireGlobal(claims: claims, method: "service.reload")

        let (config, report) = try ConfigLoader.loadResolved(
            configPath: configPath,
            instanceHome: instanceHome
        )
        let diff = await supervisor.reload(config.services)

        await configSnapshot.updateServices(from: report)

        var result: [String: JSONValue] = ["reloaded": true]

        for (key, names) in diff { result[key] = .array(names.map(JSONValue.string)) }

        return .object(result)
    }

    // MARK: - Private
}
