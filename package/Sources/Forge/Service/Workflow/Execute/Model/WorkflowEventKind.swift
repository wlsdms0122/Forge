//
//  WorkflowEventKind.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

enum WorkflowEventKind: String, Sendable, Codable {
    case workflowStarted = "workflow.started"
    case workflowCompleted = "workflow.completed"
    case workflowFailed = "workflow.failed"
    case stepStarted = "step.started"
    case stepCompleted = "step.completed"
    case stepFailed = "step.failed"
    case stepSkipped = "step.skipped"
}
