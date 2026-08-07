//
//  PolicyCheckCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct PolicyCheckCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Test if a principal may dispatch a workflow.",
        discussion: """
            forge policy check <principal> <workflow>

            Example values are placeholders — substitute your own principal
            (from `forge policy list`) and workflow name.

            Example: forge policy check <principal> <wf>
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Caller principal (e.g. `cli:response`).")
    var principal: String
    
    @Argument(help: "Target workflow name.")
    var workflow: String
    
    @Flag(help: "Emit JSON instead of plain text.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let socketPath = try resolveSocket(global)
        let token = resolveToken(global.token)
        let params: [String: Any] = ["principal": principal, "workflow": workflow]
        
        switch callRPC(
            socketPath: socketPath,
            method: "policy.check",
            params: params,
            token: token
        ) {
        case .ok(let dictionary):
            if json {
                printJSON(dictionary)
                
                return
            }
            
            let allowed = (dictionary["allowed"] as? Bool) ?? false
            let principal = (dictionary["principal"] as? String) ?? principal
            let workflow = (dictionary["workflow"] as? String) ?? workflow
            
            print("\(principal) → \(workflow): \(allowed ? "allowed" : "denied")")
            
            if !allowed { ForgeCommand.exit(withError: ExitCode(1)) }
        
        case .err(let type, let message):
            dieRPC("policy check", type: type, message: message)
        }
    }
    
    // MARK: - Private
}
