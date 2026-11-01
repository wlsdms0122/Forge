//
//  WorkflowDescribeMethod.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct WorkflowDescribeMethod: Sendable {
    // MARK: - Property
    let workflows: WorkflowReader

    // MARK: - Initializer
    init(workflows: WorkflowReader) {
        self.workflows = workflows
    }

    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        guard let path = request.params["path"]?.stringValue, !path.isEmpty else {
            throw ProtocolError("workflow.describe: 'path' (string) required")
        }

        let workflow = try await workflows.workflow(at: path)
        let contract = workflow.contract
        var result: [String: JSONValue] = [
            "path":    .string(workflow.path),
            "inputs":  .object(Self.inputs(of: contract)),
            "returns": .string(contract.returns)
        ]

        result["description"] = workflow.description.map(JSONValue.string)

        return .object(result)
    }

    // MARK: - Private
    // Each input by name, with its type and the hint the file writes.
    private static func inputs(of contract: WorkflowContract) -> [String: JSONValue] {
        Dictionary(
            contract.inputs.map { input in
                var described: [String: JSONValue] = ["type": .string(input.type)]

                if let hint = input.hint { described["hint"] = .string(hint) }

                return (input.name, .object(described))
            },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
