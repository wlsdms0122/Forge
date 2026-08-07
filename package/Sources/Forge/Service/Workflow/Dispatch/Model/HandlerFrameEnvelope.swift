//
//  HandlerFrameEnvelope.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct HandlerFrameEnvelope: Sendable {
    // MARK: - Property
    let workflowID: String
    let origin: DispatchOrigin
    let rootID: String?
    let nodeID: String?
    let correlator: String?
    
    var originDict: [String: Any] {
        var dictionary: [String: Any] = ["kind": origin.kind]
        
        if let id = origin.id { dictionary["id"] = id }
        
        return dictionary
    }
    
    // MARK: - Initializer
    init(
        workflowID: String,
        origin: DispatchOrigin,
        rootID: String?,
        nodeID: String?,
        correlator: String?
    ) {
        self.workflowID = workflowID
        self.origin = origin
        self.rootID = rootID
        self.nodeID = nodeID
        self.correlator = correlator
    }
    
    // MARK: - Public
    // MARK: - Private
}
