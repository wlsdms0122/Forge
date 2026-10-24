//
//  WorkflowCheckCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

struct WorkflowCheckCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Check workflow YAML file(s) the way the daemon reads them. Runs without a daemon.",
        discussion: """
            Reads the files together through the YAML front end, each leaning on
            Forge's library and on the others, and loads the document each one
            writes, as the daemon reads its catalog. A file that calls another
            workflow by name is checked with that workflow's file. Designed for
            CI / pre-commit hooks.

            Catches:
              - malformed YAML, a notation the front end cannot read
              - a document the load refuses
              - a file that does not declare one procedure named after it
              - ${ in a plain string, which ships as text

            Does not build, so what the build judges (types, declared
            failures, calls to names no module declares) shows when a run
            builds the workflow.

            Exits with code 1 if any file fails. Multiple paths may be passed;
            the shell expands globs.

            EXAMPLE
                forge workflow check .forge/workflow/**/*.yaml
            """
    )
    
    @Argument(help: "Path(s) to workflow YAML file(s). Globs are expanded by the shell.")
    var paths: [String]
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        guard !paths.isEmpty else {
            die("check: at least one file path is required (e.g. forge workflow check .forge/workflow/**/*.yaml)", code: 2)
        }
        
        var failed = 0
        
        for report in WorkflowLint.check(paths: paths) {
            let path = report.path
            
            if let readError = report.readError {
                print("✗ \(path): cannot read — \(readError)")
                failed += 1
            } else if let decodeError = report.decodeError {
                print("✗ \(path): decode failed")
                print("    \(decodeError)")
                failed += 1
            } else if report.issues.isEmpty {
                print("✓ \(path)")
            } else {
                print("✗ \(path) — \(report.issues.count) issue(s)")
                
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
