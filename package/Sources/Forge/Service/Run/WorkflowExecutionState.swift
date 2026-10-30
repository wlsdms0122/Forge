//
//  WorkflowExecutionState.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum WorkflowExecutionState {
    @TaskLocal static var context: WorkflowExecutionContext?
    @TaskLocal static var accessToken: String?
}
