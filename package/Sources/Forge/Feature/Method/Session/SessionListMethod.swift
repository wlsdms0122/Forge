//
//  SessionListMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct SessionListMethod: Sendable {
    // MARK: - Property
    let handlerBus: WorkflowHandlerBus

    // MARK: - Initializer
    init(handlerBus: WorkflowHandlerBus) {
        self.handlerBus = handlerBus
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        let entries = await handlerBus.listing()
        let services: [JSONValue] = entries.map { name, schema in
            var row: [String: JSONValue] = ["service": .string(name)]

            row["schema"] = schema

            return .object(row)
        }

        return ["services": .array(services)]
    }

    // MARK: - Private
}
