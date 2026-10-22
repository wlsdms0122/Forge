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

        // A workflow file declares one procedure named after the file — that is
        // Forge's convention, enforced at load, and what makes this lookup total.
        guard let procedure = entry.module.procedures[try Name(entry.name)] else {
            throw ResolutionError("workflow '\(name)' declares no procedure of that name")
        }

        var result: [String: Any] = [
            "name":        entry.name,
            "source":      entry.source,
        ]

        result["inputs"] = contract.inputs(of: procedure.signature)
        result["returns"] = contract.returns(of: procedure.signature)

        return JSONObject(result)
    }

    // MARK: - Private
}
