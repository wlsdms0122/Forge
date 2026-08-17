//
//  ShellAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

struct ShellAction: Warp.Effect {
    // MARK: - Property


    // MARK: - Initializer
    // MARK: - Public
    func run(_ invocation: Warp.Invocation) async throws -> Warp.Value {
        let host = try ForgeHost.from(invocation)
        let resolver = invocation.resolver

        guard case .array(let command) = try invocation.resolve("command"), !command.isEmpty else {
            throw ValidationError("shell.command is empty")
        }

        let arguments = command.map(resolver.stringify)
        let cwd = try invocation.string("cwd")
        let stdin = try invocation.string("stdin")
        let stepID = invocation.label
        let timeout = ValueBridge.number(try invocation.resolve("timeout"))

        let env: [String: String]

        if case .object(let written) = try invocation.resolve("env") {
            env = written.mapValues(resolver.stringify)
        } else {
            env = [:]
        }

        let declarations = try ValueBridge.decode(
            [String: OutputSpec].self,
            from: try invocation.resolve("outputs")
        )

        let result = try await host.withStepSlot {
            try await withHostDeadline(seconds: timeout) {
                try await host.shell.run(
                    executable: arguments[0],
                    args: Array(arguments.dropFirst()),
                    cwd: cwd,
                    env: env,
                    stdin: stdin,
                    stepID: stepID
                )
            }
        }

        guard result.exitCode == 0 else {
            let trimmed = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = trimmed.isEmpty
                ? String(result.stdout.suffix(300))
                : String(trimmed.prefix(300))

            throw BackendNonzeroExit(
                "shell exit \(result.exitCode): \(detail)",
                exitCode: result.exitCode,
                stderr: result.stderr,
                stdout: result.stdout
            )
        }

        let extracted = try OutputExtractor.resolve(
            stdout: result.stdout,
            declarations: declarations
        )

        return ValueBridge.value(extracted)
    }

    // MARK: - Private
}
