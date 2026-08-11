//
//  ScheduleDeleteCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct ScheduleDeleteCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a schedule.",
        discussion: """
            Deletes a schedule by id — regardless of origin (config or runtime).
            Deleting a hand-authored config file removes it from the working
            tree; restore it from the repo if needed.
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Schedule id.")
    var id: String
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "schedule delete")
        
        printResult(client.call("schedule.delete", ["id": id]), json: json)
    }
    
    // MARK: - Private
}
