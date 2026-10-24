//
//  PolicyCheckMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct PolicyCheckMethod: Sendable {
    // MARK: - Property
    let store: PolicyStore

    // MARK: - Initializer
    init(store: PolicyStore) {
        self.store = store
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        guard let principal = request.params["principal"] as? String, !principal.isEmpty else {
            throw ProtocolError("policy.check: 'principal' (string) required")
        }

        guard let workflow = request.params["workflow"] as? String, !workflow.isEmpty else {
            throw ProtocolError("policy.check: 'workflow' (string) required")
        }

        let allowed = await store.allows(principal: principal, workflow: workflow)

        return [
            "principal": principal,
            "workflow":  workflow,
            "allowed":   allowed,
        ]
    }

    // MARK: - Private
}
