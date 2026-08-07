//
//  WorkflowCancelMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

struct WorkflowCancelMethod: Sendable {
    // MARK: - Property
    let pool: WorkflowPool
    let policyStore: PolicyStore
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(pool: WorkflowPool, policyStore: PolicyStore, tokenAuthority: TokenAuthority) {
        self.pool = pool
        self.policyStore = policyStore
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        let claims = try tokenAuthority.requireClaims(request.params)

        guard let id = request.params["workflow_id"] as? String, !id.isEmpty else {
            throw ProtocolError("workflow.cancel: 'workflow_id' (string) required")
        }

        try await DispatchAuthz.requireRunControl(
            claims: claims,
            runID: id,
            pool: pool,
            policyStore: policyStore,
            context: "workflow.cancel"
        )

        let cancelled = await pool.cancel(workflowID: id)

        return ["cancelled": cancelled, "workflow_id": id]
    }

    // MARK: - Private
}
