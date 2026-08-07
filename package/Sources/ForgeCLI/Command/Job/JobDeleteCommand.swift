//
//  JobDeleteCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct JobDeleteCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a job ticket after its result has been reviewed.",
        discussion: """
            A ticket persists for review even after the work is finished — it never
            auto-expires. Once its result has been checked, `delete` removes the
            ticket (and unlinks it from its parent's children).
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Job id.")
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
            method: "job.delete",
            params: ["id": id],
            token: token
        ) {
        case .ok(let dict):
            if json { printJSON(dict) } else { print(renderResultPlain(dict)) }
        
        case .err(let type, let message):
            dieRPC("job delete", type: type, message: message)
        }
    }
    
    // MARK: - Private
}
