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
    let serviceBus: ServiceBus

    // MARK: - Initializer
    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        let records = await supervisor.statuses()
        let registered = Set(await serviceBus.listing().map(\.0))
        let services: [JSONValue] = records.map { record in
            var object = record.fields
            object["registered"] = .bool(registered.contains(record.name))

            return .object(object)
        }

        return ["services": .array(services)]
    }

    // MARK: - Private
}
