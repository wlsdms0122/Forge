//
//  WorkflowCancelMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct WorkflowCancelMethod: Sendable {
    // MARK: - Property
    let pool: WorkflowPool
    let policyStore: PolicyStore

    // MARK: - Initializer
    init(pool: WorkflowPool, policyStore: PolicyStore) {
        self.pool = pool
        self.policyStore = policyStore
    }

    // MARK: - Public
    func handle(_ request: RPCRequest, claims: TokenClaims) async throws -> JSONValue {
        guard let id = request.params["workflow_id"]?.stringValue, !id.isEmpty else {
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

        return ["cancelled": .bool(cancelled), "workflow_id": .string(id)]
    }

    // MARK: - Private
}
