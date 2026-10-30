//
//  ResourceCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
//

import ArgumentParser
import Foundation

struct ResourceCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "resource",
        abstract: "List or read files under the document root.",
        discussion: """
            Single gate over the document root. External tools (admin, scripts, agents) read
            resources through the daemon instead of touching the filesystem directly, so
            anchor/escape checks and hot reload are enforced in one place.
            """,
        subcommands: [ResourceListCommand.self, ResourceReadCommand.self]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
