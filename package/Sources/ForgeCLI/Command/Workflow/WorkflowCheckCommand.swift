//
//  WorkflowCheckCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

struct WorkflowCheckCommand: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Check workflow YAML file(s) the way the daemon reads them. Runs without a daemon.",
        discussion: """
            Reads each file as the daemon reads one: through
            the YAML front end leaning on Forge's library, loaded, held to
            Forge's convention, and built against the library, the natives and
            std. Designed for CI / pre-commit hooks.

            Catches:
              - malformed YAML, a notation the front end cannot read
              - a document the load refuses
              - a file that does not declare a public procedure `main`
              - a file the build refuses
              - ${ in a plain string, which ships as text

            Exits with code 1 if any file fails. Multiple paths may be passed;
            the shell expands globs.

            EXAMPLE
                forge workflow check .forge/document/**/*.yaml
            """
    )
    
    @Argument(help: "Path(s) to workflow YAML file(s). Globs are expanded by the shell.")
    var paths: [String]
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        var failed = 0
        
        for report in try await WorkflowLint().check(paths: paths) {
            let path = report.path
            
            if let readError = report.readError {
                print("✗ \(path): cannot read: \(readError)")
                failed += 1
            } else if let refusal = report.refusal {
                print("✗ \(path): refused")
                print("    \(refusal)")
                failed += 1
            } else if report.issues.isEmpty {
                print("✓ \(path)")
            } else {
                print("✗ \(path): \(report.issues.count) issue(s)")
                
                for issue in report.issues {
                    print("    \(issue)")
                }
                
                failed += 1
            }
        }
        
        if failed > 0 {
            FileHandle.standardError.write(Data("\n\(failed) file(s) failed\n".utf8))
            
            throw ExitCode(1)
        }
    }
    
    // MARK: - Private
}
