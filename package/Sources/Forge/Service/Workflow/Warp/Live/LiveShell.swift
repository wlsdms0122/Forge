//
//  LiveShell.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// The live process seam — `Subprocess` already terminates the process tree on
// task cancellation, which is what the seam contract demands.
struct LiveShell: ShellExecuting {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func run(
        executable: String,
        args: [String],
        cwd: String?,
        env: [String: String],
        stdin: String?,
        stepID: String?
    ) async throws -> ShellRunOutput {
        let envExtra = SubprocessEnv.merge(
            baseline: SubprocessEnv.baseline(),
            specOverride: env
        )
        let invocationID = UUID().uuidString

        await ShellLog.request(
            invocationID: invocationID,
            stepID: stepID,
            executable: executable,
            args: args,
            cwd: cwd,
            stdin: stdin
        )

        let started = ContinuousClock.now
        let result: SubprocessResult

        do {
            result = try await Subprocess.run(
                executable: executable,
                args: args,
                cwd: cwd,
                envExtra: envExtra,
                stdin: stdin
            )
        } catch {
            await ShellLog.error(
                invocationID: invocationID,
                stepID: stepID,
                executable: executable,
                error: error,
                durationMs: (ContinuousClock.now - started).milliseconds
            )

            throw error
        }

        await ShellLog.response(
            invocationID: invocationID,
            stepID: stepID,
            executable: executable,
            exitCode: Int(result.exitCode),
            durationMs: (ContinuousClock.now - started).milliseconds,
            stdout: result.stdout,
            stderr: result.stderr
        )

        return ShellRunOutput(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }

    // MARK: - Private
}
