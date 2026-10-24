//
//  ShellAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

struct ShellAction: Warp.Effect {
    enum Parameters: Int, ParameterSet {
        case command
        case cwd
        case env
        case stdin
        case outputs
        case timeout

        // MARK: - Property
        var declared: Parameter {
            switch self {
            case .command:
                Parameter(name: "command", type: .array(.string))

            case .cwd:
                Parameter(name: "cwd", type: .optional(.string))

            case .env:
                Parameter(name: "env", type: .optional(.dictionary(key: .string, value: .string)))

            case .stdin:
                Parameter(name: "stdin", type: .optional(.string))

            case .outputs:
                Parameter(name: "outputs", type: .optional(.dictionary(key: .string, value: .any)))

            case .timeout:
                Parameter(name: "timeout", type: .optional(.double))
            }
        }

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func run(_ invocation: Warp.Invocation<Self>) async throws -> Warp.Value {
        let environment = try ForgeEnvironment.from(invocation)

        guard case let .array(command) = invocation[.command], !command.isEmpty else {
            throw ExecutionError("shell.command is empty")
        }

        let arguments = command.map(ValueBridge.text)
        let env = try ValueBridge.strings(invocation[.env])
        let declarations = try ValueBridge.decode(
            [String: OutputSpec].self,
            from: invocation[.outputs]
        )
        let result = try await environment.withStepSlot {
            try await withDeadline(seconds: ValueBridge.number(invocation[.timeout])) {
                try await environment.shell.run(
                    executable: arguments[0],
                    args: Array(arguments.dropFirst()),
                    cwd: invocation.string(.cwd),
                    env: env,
                    stdin: invocation.string(.stdin),
                    stepID: invocation.trace.step
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

        return try ValueBridge.value(
            try OutputExtractor.resolve(stdout: result.stdout, declarations: declarations)
        )
    }

    // MARK: - Private
}
