//
//  WorkflowCancelCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

struct WorkflowCancelCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "cancel",
        abstract: "Cancel a queued or running workflow."
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Run id to cancel.")
    var runID: String
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "workflow cancel")
        
        client.call("workflow.cancel", ["run_id": .string(runID)]).printResult(json: json)
    }
    
    // MARK: - Private
}
