//
//  ServiceListMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ServiceListMethod: Sendable {
    // MARK: - Property
    let serviceBus: ServiceBus

    // MARK: - Initializer
    init(serviceBus: ServiceBus) {
        self.serviceBus = serviceBus
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        let entries = await serviceBus.listing()
        let services: [JSONValue] = entries.map { name, schema in
            var row: [String: JSONValue] = ["service": .string(name)]

            row["schema"] = schema

            return .object(row)
        }

        return ["services": .array(services)]
    }

    // MARK: - Private
}
