//
//  ShellAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

struct ShellAction: ForgeAction {
    enum Parameters: Int, ParameterSet {
        case command
        case cwd
        case env
        case stdin
        case timeout

        // MARK: - Property
        var declared: Parameter {
            switch self {
            case .command:
                Parameter(name: "command", type: .array(.string))

            case .cwd:
                Parameter(name: "cwd", type: .optional(.string))

            case .env:
                Parameter(name: "env", type: .dictionary(key: .string, value: .string))

            case .stdin:
                Parameter(name: "stdin", type: .optional(.string))

            case .timeout:
                Parameter(name: "timeout", type: .optional(.double))
            }
        }

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    static let signature = Signature(
        of: Self.self,
        returns: .string,
        failing: .these([BackendNonzeroExit.type, DeadlineExceeded.type]),
        isolation: .isolated
    )

    // MARK: - Initializer
    // MARK: - Public
    func act(_ invocation: Warp.Invocation<Self>, in environment: ForgeEnvironment) async throws -> Warp.Value {
        guard case let .array(command) = invocation[.command], !command.isEmpty else {
            throw ExecutionError("shell.command is empty")
        }

        let arguments = command.map(ValueBridge.text)
        let env = try ValueBridge.strings(invocation[.env])
        let step = invocation.trace.step(sentFrom: environment.bridge.verbs)
        let result = try await environment.withStepSlot {
            try await withDeadline(seconds: ValueBridge.number(invocation[.timeout])) {
                try await environment.shell.run(
                    executable: arguments[0],
                    args: Array(arguments.dropFirst()),
                    cwd: invocation.string(.cwd),
                    env: env,
                    stdin: invocation.string(.stdin),
                    stepID: step
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

        return .string(result.stdout)
    }

    // MARK: - Private
}
