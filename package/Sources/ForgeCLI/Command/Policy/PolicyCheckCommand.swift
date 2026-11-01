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

            Example values are placeholders; substitute your own principal
            (from `forge policy list`) and workflow path.

            Example: forge policy check <principal> <path>
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Caller principal (e.g. `cli:bot/response.yaml`).")
    var principal: String
    
    @Argument(help: "Target workflow, by its path as dispatched.")
    var workflow: String
    
    @Flag(help: "Emit JSON instead of plain text.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "policy check")
        let result = client.call("policy.check", ["principal": .string(principal), "workflow": .string(workflow)])
        
        if json {
            result.printJSON()
            
            return
        }
        
        let allowed = result["allowed"]?.boolValue ?? false
        let principal = result["principal"]?.stringValue ?? principal
        let workflow = result["workflow"]?.stringValue ?? workflow
        
        print("\(principal) → \(workflow): \(allowed ? "allowed" : "denied")")
        
        if !allowed { Self.exit(withError: ExitCode(1)) }
    }
    
    // MARK: - Private
}
