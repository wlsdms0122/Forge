//
//  ServiceStatusMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ServiceStatusMethod: Sendable {
    // MARK: - Property
    let supervisor: ServiceSupervisor
    let handlerBus: WorkflowHandlerBus
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        _ = try tokenAuthority.requireClaims(request.params)

        let records = await supervisor.statuses()
        let registered = Set(await handlerBus.listing().map(\.0))
        let services: [[String: Any]] = records.map { record in
            var dictionary = record.dict
            dictionary["registered"] = registered.contains(record.name)

            return dictionary
        }

        return JSONObject(["services": services])
    }

    // MARK: - Private
}
