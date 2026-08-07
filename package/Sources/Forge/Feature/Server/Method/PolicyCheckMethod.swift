//
//  PolicyCheckMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

struct PolicyCheckMethod: Sendable {
    // MARK: - Property
    let store: PolicyStore
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(store: PolicyStore, tokenAuthority: TokenAuthority) {
        self.store = store
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        _ = try tokenAuthority.requireClaims(request.params)

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
