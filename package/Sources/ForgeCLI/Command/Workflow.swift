//
//  Workflow.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
//

import ArgumentParser
import Foundation
import Forge

struct WorkflowCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "workflow",
        abstract: "Dispatch and inspect workflow runs.",
        subcommands: [
            WorkflowDispatchCommand.self,
            WorkflowListCommand.self,
            WorkflowDescribeCommand.self,
            WorkflowActiveCommand.self,
            WorkflowHealthCommand.self,
            WorkflowCancelCommand.self,
            WorkflowCheckCommand.self,
        ]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
