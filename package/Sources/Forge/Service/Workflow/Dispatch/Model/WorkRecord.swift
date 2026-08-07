//
//  WorkRecord.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct WorkRecord: Sendable {
    // MARK: - Property
    let workflowID: String
    let workflowName: String
    let principal: String
    let origin: DispatchOrigin
    let rootID: String?
    let nodeID: String?
    let correlator: String?
    let parameters: [String: JSONValue]?
    
    // MARK: - Initializer
    // MARK: - Public
    func withNodeID(_ nodeID: String?) -> WorkRecord {
        WorkRecord(
            workflowID: workflowID,
            workflowName: workflowName,
            principal: principal,
            origin: origin,
            rootID: rootID,
            nodeID: nodeID,
            correlator: correlator,
            parameters: parameters
        )
    }
    
    // MARK: - Private
}
