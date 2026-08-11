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
        let client = Client(global, context: "policy check")
        let params: [String: Any] = ["principal": principal, "workflow": workflow]
        
        let result = client.call("policy.check", params)
        
        if json {
            printJSON(result)
            
            return
        }
        
        let allowed = (result["allowed"] as? Bool) ?? false
        let principal = (result["principal"] as? String) ?? principal
        let workflow = (result["workflow"] as? String) ?? workflow
        
        print("\(principal) → \(workflow): \(allowed ? "allowed" : "denied")")
        
        if !allowed { ForgeCommand.exit(withError: ExitCode(1)) }
    }
    
    // MARK: - Private
}
