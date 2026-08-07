//
//  SessionListMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

struct SessionListMethod: Sendable {
    // MARK: - Property
    let handlerBus: WorkflowHandlerBus
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(handlerBus: WorkflowHandlerBus, tokenAuthority: TokenAuthority) {
        self.handlerBus = handlerBus
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        _ = try tokenAuthority.requireClaims(request.params)

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
