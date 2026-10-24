//
//  WorkflowExecutionContext.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct WorkflowExecutionContext: Sendable {
    // MARK: - Property
    let workflowID: String
    let workflowName: String
    let origin: DispatchOrigin
    
    var asPayload: [String: Any] {
        [
            "workflow_id": workflowID,
            "workflow_name": workflowName,
            "origin": origin.asPayload
        ]
    }
    
    // MARK: - Initializer
    init(workflowID: String, workflowName: String, origin: DispatchOrigin) {
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.origin = origin
    }
    
    // MARK: - Public
    // MARK: - Private
}
