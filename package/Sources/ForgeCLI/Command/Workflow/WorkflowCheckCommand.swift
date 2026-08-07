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
        abstract: "Lint workflow YAML file(s) — decode + validator. Runs without a daemon.",
        discussion: """
            Decodes each file as a Workflow then runs the same WorkflowValidator
            the daemon uses at load time. Designed for CI / pre-commit hooks.

            Catches:
              - malformed YAML / broken spec structure
              - half-spelled expression forms ({ ref: }, { value: }, { format: })
              - { ref: inputs.X } where X is not declared
              - { ref: step.X } where step is not a visible id
              - format templates naming a binding not declared in `with`

            Does NOT catch (intentional limits):
              - { ref: step.X.Y } — Y (output key) is not checked
              - cross-workflow refs (dispatch child outputs)
              - refs that depend on runtime JSON shape

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
        
        for path in paths {
            let report = WorkflowLint.check(path: path)
            
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
