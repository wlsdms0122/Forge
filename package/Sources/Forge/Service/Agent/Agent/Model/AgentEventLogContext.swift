//
//  AgentEventLogContext.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct AgentEventLogContext: Sendable {
    // MARK: - Property
    static var current: AgentEventLogContext {
        AgentEventLogContext(
            rootIdentifier: LogContext.rootID,
            nodeIdentifier: LogContext.nodeID,
            parentNodeIdentifier: LogContext.parentNodeID,
            parameters: LogContext.parameters,
            metadata: LogContext.metadata
        )
    }

    let rootIdentifier: String?
    let nodeIdentifier: String?
    let parentNodeIdentifier: String?
    let parameters: [String: JSONValue]?
    let metadata: LogPayload?

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
