//
//  ScheduleDeleteMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

struct ScheduleDeleteMethod: Sendable {
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

        guard let id = request.params["id"] as? String, !id.isEmpty else {
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
