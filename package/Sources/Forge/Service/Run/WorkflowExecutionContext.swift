//
//  WorkflowExecutionContext.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct WorkflowExecutionContext: Sendable {
    // MARK: - Property
    let runID: String
    let workflowName: String
    let origin: DispatchOrigin
    
    var asPayload: [String: Any] {
        [
            "workflow_id": runID,
            "workflow_name": workflowName,
            "origin": origin.jsonValue.jsonObject
        ]
    }
    
    // MARK: - Initializer
    init(runID: String, workflowName: String, origin: DispatchOrigin) {
        self.runID = runID
        self.workflowName = workflowName
        self.origin = origin
    }
    
    // MARK: - Public
    // MARK: - Private
}
