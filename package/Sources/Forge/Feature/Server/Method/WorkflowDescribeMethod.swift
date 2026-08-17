//
//  WorkflowDescribeMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

struct WorkflowDescribeMethod: Sendable {
    // MARK: - Property
    let store: SpecCatalog
    let tokenAuthority: TokenAuthority

    private let contract = WorkflowContract()

    // MARK: - Initializer
    init(store: SpecCatalog, tokenAuthority: TokenAuthority) {
        self.store = store
        self.tokenAuthority = tokenAuthority
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        _ = try tokenAuthority.requireClaims(request.params)

        guard let name = request.params["name"] as? String, !name.isEmpty else {
            throw ProtocolError("workflow.describe: 'name' (string) required")
        }

        let entries = await store.catalog().entries

        guard let entry = entries.first(where: { entry in entry.name == name }) else {
            throw ResolutionError("workflow not found: \(name)")
        }

        // A workflow file declares one routine named after the file — that is
        // Forge's convention, enforced at load, and what makes this lookup total.
        guard let routine = entry.module.procedures[entry.name] else {
            throw ResolutionError("workflow '\(name)' declares no routine of that name")
        }

        var result: [String: Any] = [
            "name":        entry.name,
            "description": routine.description as Any? ?? NSNull(),
            "source":      entry.source,
        ]

        result["inputs"] = try contract.inputs(of: routine.signature)
        result["outputs"] = try contract.outputs(of: routine.result)

        return JSONObject(result)
    }

    // MARK: - Private
}
