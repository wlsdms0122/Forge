//
//  GlobalOptions.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct GlobalOptions: ParsableArguments {
    // MARK: - Property
    @Option(help: "Session name — selects the daemon socket (default: default).")
    var session: String?
    
    @Option(help: "Daemon-signed bearer token (overrides FORGE_ACCESS_TOKEN).")
    var token: String?
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
