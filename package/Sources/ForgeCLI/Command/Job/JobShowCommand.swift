//
//  JobShowCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

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
        
        printResult(client.call("job.show", ["id": id]), json: json)
    }
    
    // MARK: - Private
}
