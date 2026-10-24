//
//  ScheduleDeleteMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ScheduleDeleteMethod: Sendable {
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
        guard let id = request.rawParams["id"] as? String, !id.isEmpty else {
            throw ProtocolError("schedule.delete: 'id' (string) required")
        }

        let authorized = try await DispatchAuthz.requireScheduleControl(
            claims: claims,
            scheduleID: id,
            store: store,
            policyStore: policyStore,
            context: "schedule.delete"
        )

        try await store.delete(id: id, authorizedWorkflow: authorized.workflow)

        return ["id": id, "deleted": true]
    }

    // MARK: - Private
}
