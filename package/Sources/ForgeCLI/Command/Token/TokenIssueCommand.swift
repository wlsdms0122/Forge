//
//  TokenIssueCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct TokenIssueCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "issue",
        abstract: "Mint a bearer token for a principal."
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Principal to mint for (system:runner | system:admin | admin:<user>).")
    var principal: String
    
    @Flag(help: "Emit the full JSON response (default: token string only).")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "token issue")
        let result = client.call("token.issue", ["principal": principal])
        
        if json {
            printJSON(result)
        } else {
            print((result["token"] as? String) ?? "")
        }
        
        ForgeCommand.exit()
    }
    
    // MARK: - Private
}
