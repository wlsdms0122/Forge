//
//  LogRecord.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
@testable import Forge

/// One JSONL line that `Log` wrote to the sink.
struct LogRecord: Decodable {
    // MARK: - Property
    let kind: String
    let category: String
    let level: String
    let nodeID: String?
    let parentNodeID: String?
    let rootID: String?
    let payload: [String: JSONValue]
    let parameters: [String: JSONValue]

    // MARK: - Initializer
    // MARK: - Public
    /// The workflow this record belongs to. If absent, the log came from outside a workflow.
    var workflowID: String? {
        guard case .string(let identifier) = payload["workflow_id"] else { return nil }

        return identifier
    }

    // MARK: - Private
    private enum CodingKeys: String, CodingKey {
        case kind
        case category
        case level
        case nodeID = "id"
        case parentNodeID = "parent_id"
        case rootID = "root_id"
        case payload
        case parameters
    }
}
