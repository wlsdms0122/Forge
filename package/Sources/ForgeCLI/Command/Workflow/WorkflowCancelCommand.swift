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
        let client = Client(global, context: "workflow cancel")
        
        printResult(client.call("workflow.cancel", ["workflow_id": workflowID]), json: json)
    }
    
    // MARK: - Private
}
