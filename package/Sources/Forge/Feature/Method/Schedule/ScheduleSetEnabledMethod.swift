//
//  ScheduleSetEnabledMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ScheduleSetEnabledMethod: Sendable {
    // MARK: - Property
    let store: ScheduleStore
    let policyStore: PolicyStore

    // MARK: - Initializer
    init(store: ScheduleStore, policyStore: PolicyStore) {
        self.store = store
        self.policyStore = policyStore
    }

    // MARK: - Public
    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONObject {
        guard let id = request.rawParams["id"] as? String else {
            throw ProtocolError("schedule.set_enabled: 'id' (string) required")
        }

        guard let enabled = request.rawParams["enabled"] as? Bool else {
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
