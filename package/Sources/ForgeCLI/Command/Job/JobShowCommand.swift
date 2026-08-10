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
        let socketPath = try resolveSocket(global)
        let token = resolveToken(global.token)
        
        switch callRPC(
            socketPath: socketPath,
            method: "job.show",
            params: ["id": id],
            token: token
        ) {
        case .ok(let dict):
            if json { printJSON(dict) } else { print(renderResultPlain(dict)) }
        
        case .err(let type, let message):
            dieRPC("job show", type: type, message: message)
        }
    }
    
    // MARK: - Private
}
