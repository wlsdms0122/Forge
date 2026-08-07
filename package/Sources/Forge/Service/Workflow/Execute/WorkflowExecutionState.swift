//
//  WorkflowExecutionState.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum WorkflowExecutionState {
    @TaskLocal static var agentSession: AgentSession?
    @TaskLocal static var accessToken: String?
    @TaskLocal static var accessTokenID: String?
}
