//
//  ScheduleDeleteCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

struct ScheduleDeleteCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a schedule.",
        discussion: """
            Deletes a schedule by id.
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
        
        client.call("schedule.delete", ["id": .string(id)]).printResult(json: json)
    }
    
    // MARK: - Private
}
