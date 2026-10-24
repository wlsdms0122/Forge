//
//  HandlerFrameEnvelope.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct HandlerFrameEnvelope: Sendable {
    // MARK: - Property
    let runID: String
    let origin: DispatchOrigin
    let rootID: String?
    let nodeID: String?
    let correlator: String?
    

    
    // MARK: - Initializer
    init(
        runID: String,
        origin: DispatchOrigin,
        rootID: String?,
        nodeID: String?,
        correlator: String?
    ) {
        self.runID = runID
        self.origin = origin
        self.rootID = rootID
        self.nodeID = nodeID
        self.correlator = correlator
    }
    
    // MARK: - Public
    // MARK: - Private
}
