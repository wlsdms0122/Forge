//
//  JobShowCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

struct JobShowCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a job ticket in full (brief, refs, plan, comments, events, children)."
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Job id.")
    var id: String
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "job show")
        
        client.call("job.show", ["id": .string(id)]).printResult(json: json)
    }
    
    // MARK: - Private
}
