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
        let socketPath = try resolveSocket(global)
        let token = resolveToken(global.token)
        
        switch callRPC(
            socketPath: socketPath,
            method: "schedule.delete",
            params: ["id": id],
            token: token
        ) {
        case .ok(let dict):
            if json { printJSON(dict) } else { print(renderResultPlain(dict)) }
        
        case .err(let type, let message):
            dieRPC("schedule delete", type: type, message: message)
        }
    }
    
    // MARK: - Private
}
