//
//  PackageVersion.swift
//  PackageVersion
//
//  Created by JSilver on 11/1/26.
//

import Foundation
import PackagePlugin

// Gives the target it is applied to `packageVersion`, read at every build
// from the open-package manifest beside the Swift package.
@main
struct PackageVersion: BuildToolPlugin {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Lifecycle
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let manifest = context.package.directoryURL.appending(path: "../manifest.toml").standardized
        let output = context.pluginWorkDirectoryURL.appending(path: "PackageVersion.swift")

        return [
            .buildCommand(
                displayName: "Reading [package] version from \(manifest.path)",
                executable: try context.tool(named: "PackageVersionTool").url,
                arguments: [manifest.path, output.path],
                inputFiles: [manifest],
                outputFiles: [output]
            )
        ]
    }

    // MARK: - Public
    // MARK: - Private
}
