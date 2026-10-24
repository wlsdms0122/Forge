//
//  WorkflowDescribeMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct WorkflowDescribeMethod: Sendable {
    // MARK: - Property
    let store: WorkflowCatalog
    let tokenAuthority: TokenAuthority

    // MARK: - Initializer
    init(store: WorkflowCatalog, tokenAuthority: TokenAuthority) {
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

        guard let entry = entries.first(where: { entry in entry.workflow.name == name }) else {
            throw ResolutionError("workflow not found: \(name)")
        }

        let contract = entry.workflow.contract
        var result: [String: Any] = [
            "name":        entry.workflow.name,
            "source":      entry.source,
        ]

        result["description"] = entry.workflow.description
        result["inputs"] = Self.inputs(of: contract)
        result["returns"] = contract.returns

        return JSONObject(result)
    }

    // MARK: - Private
    // Each input by name, with its type, and the default and the hint the
    // file writes.
    private static func inputs(of contract: WorkflowContract) -> [String: Any] {
        Dictionary(
            contract.inputs.map { input in
                var described: [String: Any] = ["type": input.type]

                if let written = input.defaultValue { described["default"] = jsonValueToAny(written) }

                if let hint = input.hint { described["hint"] = hint }

                return (input.name, described)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
