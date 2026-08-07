//
//  Token.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
//

import ArgumentParser
import Foundation

struct TokenCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "token",
        abstract: "Issue a daemon-signed bearer token.",
        discussion: """
            The daemon signs tokens with a random seed minted at boot and
            kept only in memory — a restart invalidates every token, and
            clients re-issue on rejection.

            `token issue` is a normal authenticated RPC: it requires a token
            (FORGE_ACCESS_TOKEN / --token) like every other call, and only
            mints under attenuation — an admin-tier presenter (system:admin /
            admin:<user>) may delegate, anything else may not. A workflow
            subprocess only ever holds a cli:* token, so an LLM cannot escalate.

            The first token is not minted here: the daemon mints a bootstrap
            system:admin at boot and hands it to its launcher over an inherited
            fd (FORGE_BOOTSTRAP_FD), which then delegates as needed.

            Issuable principals: system:runner, system:admin, admin:<user>.
            cli:<workflow> tokens are minted internally at spawn only.
            """,
        subcommands: [TokenIssueCommand.self]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
