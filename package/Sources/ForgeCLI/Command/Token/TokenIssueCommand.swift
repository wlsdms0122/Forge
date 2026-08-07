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
        let socketPath = try resolveSocket(global)
        let token = resolveToken(global.token)
        
        switch callRPC(
            socketPath: socketPath,
            method: "token.issue",
            params: ["principal": principal],
            token: token
        ) {
        case .ok(let dictionary):
            if json {
                printJSON(dictionary)
            } else {
                print((dictionary["token"] as? String) ?? "")
            }
            
            ForgeCommand.exit()
        
        case .err(let type, let message):
            dieRPC("token issue", type: type, message: message)
        }
    }
    
    // MARK: - Private
}
