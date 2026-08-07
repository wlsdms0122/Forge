//
//  WorkflowCancelCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct WorkflowCancelCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "cancel",
        abstract: "Cancel a queued or running workflow."
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Workflow id to cancel.")
    var workflowID: String
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let socketPath = try resolveSocket(global)
        let token = resolveToken(global.token)
        
        switch callRPC(
            socketPath: socketPath,
            method: "workflow.cancel",
            params: ["workflow_id": workflowID],
            token: token
        ) {
        case .ok(let dict):
            if json { printJSON(dict) } else { print(renderResultPlain(dict)) }
        
        case .err(let type, let message):
            dieRPC("workflow cancel", type: type, message: message)
        }
    }
    
    // MARK: - Private
}
