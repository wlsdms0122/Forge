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
        abstract: "List or read files under the working directory.",
        discussion: """
            Single gate over the working directory. External tools (admin, scripts, agents) read
            resources through the daemon instead of touching the filesystem directly, so
            the reach (relative paths only, no hidden part, no link leading out)
            is enforced in one place.
            """,
        subcommands: [ResourceListCommand.self, ResourceReadCommand.self]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
