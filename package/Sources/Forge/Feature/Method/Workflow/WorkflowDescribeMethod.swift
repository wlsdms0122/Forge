//
//  WorkflowDescribeMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct WorkflowDescribeMethod: Sendable {
    // MARK: - Property
    let catalog: WorkflowCatalog

    // MARK: - Initializer
    init(catalog: WorkflowCatalog) {
        self.catalog = catalog
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        guard let name = request.params["name"]?.stringValue, !name.isEmpty else {
            throw ProtocolError("workflow.describe: 'name' (string) required")
        }

        let entries = await catalog.reload().entries

        guard let entry = entries.first(where: { entry in entry.workflow.name == name }) else {
            throw WorkflowNotFound("workflow not found: \(name)")
        }

        let contract = entry.workflow.contract
        var result: [String: JSONValue] = [
            "name":    .string(entry.workflow.name),
            "source":  .string(entry.source),
            "inputs":  .object(Self.inputs(of: contract)),
            "returns": .string(contract.returns)
        ]

        result["description"] = entry.workflow.description.map(JSONValue.string)

        return .object(result)
    }

    // MARK: - Private
    // Each input by name, with its type, and the default and the hint the
    // file writes.
    private static func inputs(of contract: WorkflowContract) -> [String: JSONValue] {
        Dictionary(
            contract.inputs.map { input in
                var described: [String: JSONValue] = ["type": .string(input.type)]

                if let written = input.defaultValue { described["default"] = written }

                if let hint = input.hint { described["hint"] = .string(hint) }

                return (input.name, .object(described))
            },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
