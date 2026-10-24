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
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        let entries = await handlerBus.listing()
        var services: [[String: Any]] = entries.map { name, schema in
            var row: [String: Any] = ["service": name]

            if let schema { row["schema"] = schema.dict }

            return row
        }
        services.sort { lhs, rhs in
            (lhs["service"] as? String ?? "") < (rhs["service"] as? String ?? "")
        }

        return ["services": services]
    }

    // MARK: - Private
}
