//
//  DispatchAuthorization.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum DispatchAuthorization {
    static func requireDispatch(
        claims: TokenClaims,
        workflow: String,
        policyStore: PolicyStore,
        context: String
    ) async throws {
        try await requireDispatch(
            principal: claims.principal,
            workflow: workflow,
            policyStore: policyStore,
            context: context
        )
    }
    
    static func requireDispatch(
        principal: String,
        workflow: String,
        policyStore: PolicyStore,
        context: String
    ) async throws {
        guard await policyStore.allows(principal: principal, workflow: workflow) else {
            throw PolicyDenied(
                "\(context): principal '\(principal)' is not allowed to call workflow '\(workflow)' (policy/*.yaml)"
            )
        }
    }
    
    static func requireRunControl(
        claims: TokenClaims,
        runID: String,
        pool: WorkflowPool,
        policyStore: PolicyStore,
        context: String
    ) async throws {
        guard let workflow = await pool.workflowName(of: runID) else { return }
        
        try await requireDispatch(
            claims: claims,
            workflow: workflow,
            policyStore: policyStore,
            context: context
        )
    }
}
