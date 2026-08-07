//
//  ScheduleSetEnabledMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

struct ScheduleSetEnabledMethod: Sendable {
    // MARK: - Property
    let store: ScheduleStore
    let policyStore: PolicyStore
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(store: ScheduleStore, policyStore: PolicyStore, tokenAuthority: TokenAuthority) {
        self.store = store
        self.policyStore = policyStore
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        let claims = try tokenAuthority.requireClaims(request.params)

        guard let id = request.params["id"] as? String else {
            throw ProtocolError("schedule.set_enabled: 'id' (string) required")
        }

        guard let enabled = request.params["enabled"] as? Bool else {
            throw ProtocolError("schedule.set_enabled: 'enabled' (bool) required")
        }

        let authorized = try await DispatchAuthz.requireScheduleControl(
            claims: claims,
            scheduleID: id,
            store: store,
            policyStore: policyStore,
            context: "schedule.set_enabled"
        )

        try await store.setEnabled(
            id: id,
            enabled: enabled,
            authorizedWorkflow: authorized.workflow
        )

        return ["id": id, "enabled": enabled]
    }

    // MARK: - Private
}
