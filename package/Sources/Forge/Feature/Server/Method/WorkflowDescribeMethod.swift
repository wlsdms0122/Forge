//
//  WorkflowDescribeMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

struct WorkflowDescribeMethod: Sendable {
    // MARK: - Property
    let store: SpecCatalog
    let tokenAuthority: TokenAuthority

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

        let program = entry.program
        var result: [String: Any] = [
            "name":        entry.name,
            "description": program.description as Any? ?? NSNull(),
            "source":      entry.source,
        ]

        if program.inputs.parameters.isEmpty {
            result["inputs"] = [String: Any]()
        } else {
            result["inputs"] = try encodableToAny(program.inputs)
        }

        if let outputs = program.outputs, !outputs.isEmpty {
            result["outputs"] = try encodableToAny(outputs)
        } else {
            result["outputs"] = [String: Any]()
        }

        return JSONObject(result)
    }

    // MARK: - Private
}

func encodableToAny<T: Encodable>(_ value: T) throws -> Any {
    let data = try JSONEncoder().encode(value)

    return try JSONSerialization.jsonObject(with: data)
}
