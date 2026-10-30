//
//  PolicyCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
//

import ArgumentParser
import Foundation

struct PolicyCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "policy",
        abstract: "Inspect the ACL policy that gates `workflow dispatch`.",
        discussion: """
            Every `workflow dispatch` — operator, runner, admin, or a
            nested call from inside a workflow — is gated by YAML files
            under the policy dir (`[directory] policy`, default `<instanceHome>/policy`). Each file is a flat
            mapping of principal patterns to workflow name patterns.
            Multiple files are union-merged by principal key, and changes
            hot-reload on next dispatch.

            Pattern matching:
                exact:            "cli:response"
                class wildcard:   "cli:*"
                global wildcard:  "*"

            Principal classes:
                cli:<workflow>           workflow subprocess (daemon mints)
                service:<name>           managed service (supervisor mints)
                system:admin             admin route (manual triggers)
                system:runner            slack / runner pipeline
                system:schedule:<id>     daemon's internal scheduler
                admin:<user>             named admin (token issue)
            """,
        subcommands: [
            PolicyListCommand.self,
            PolicyCheckCommand.self
        ]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
