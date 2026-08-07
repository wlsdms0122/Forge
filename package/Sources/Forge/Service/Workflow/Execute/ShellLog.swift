//
//  ShellLog.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// One shell-invocation log schema, one writer — whichever engine runs the
// process, the log consumer sees the same fields.
enum ShellLog {
    // MARK: - Property
    private static let category = "hook.logging"
    private static let stdoutPreviewLimit = 2000
    private static let stderrPreviewLimit = 500

    // MARK: - Initializer
    // MARK: - Public
    static func request(
        invocationID: String,
        stepID: String?,
        executable: String,
        args: [String],
        cwd: String?,
        stdin: String?
    ) async {
        // stdin carries whatever a spec reference resolved to — tokens and
        // credentials included — so only its length is logged, never the body.
        var payload: [String: Any] = [
            "id": invocationID,
            "executable": executable,
            "args": args,
            "cwd": cwd as Any? ?? NSNull(),
            "stdin_len": stdin?.count ?? 0
        ]

        if let stepID { payload["step"] = stepID }

        for (key, value) in forgeContext() { payload[key] = value }

        await Log.shared.append(
            "shell.request",
            LogPayload(payload),
            category: category
        )
    }

    static func response(
        invocationID: String,
        stepID: String?,
        executable: String,
        exitCode: Int,
        durationMs: Int,
        stdout: String,
        stderr: String
    ) async {
        var payload: [String: Any] = [
            "id": invocationID,
            "executable": executable,
            "exit_code": exitCode,
            "duration_ms": durationMs,
            "stdout_len": stdout.count,
            "stdout_preview": String(stdout.prefix(stdoutPreviewLimit)),
            "stderr_len": stderr.count,
            "stderr_preview": String(stderr.prefix(stderrPreviewLimit))
        ]

        if let stepID { payload["step"] = stepID }

        for (key, value) in forgeContext() { payload[key] = value }

        await Log.shared.append(
            "shell.response",
            LogPayload(payload),
            category: category
        )
    }

    static func error(
        invocationID: String,
        stepID: String?,
        executable: String,
        error: any Error,
        durationMs: Int,
        stdout: String = "",
        stderr: String = ""
    ) async {
        let errorType = String(describing: type(of: error))
        var payload: [String: Any] = [
            "id": invocationID,
            "executable": executable,
            "duration_ms": durationMs,
            "error_type": errorType
        ]

        if let stepID { payload["step"] = stepID }

        if let forgeError = error as? ForgeError { payload["message"] = forgeError.message }

        if let nonzeroExit = error as? BackendNonzeroExit {
            payload["exit_code"] = Int(nonzeroExit.exitCode)
            payload["stdout_len"] = nonzeroExit.stdout.count
            payload["stdout_preview"] = String(nonzeroExit.stdout.prefix(stdoutPreviewLimit))
            payload["stderr_len"] = nonzeroExit.stderr.count
            payload["stderr_preview"] = String(nonzeroExit.stderr.prefix(stderrPreviewLimit))
        } else if !stdout.isEmpty || !stderr.isEmpty {
            payload["stdout_len"] = stdout.count
            payload["stdout_preview"] = String(stdout.prefix(stdoutPreviewLimit))
            payload["stderr_len"] = stderr.count
            payload["stderr_preview"] = String(stderr.prefix(stderrPreviewLimit))
        }

        for (key, value) in forgeContext() { payload[key] = value }

        var errorObject: [String: Any] = ["type": errorType]

        if let forgeError = error as? ForgeError { errorObject["message"] = forgeError.message }

        if let nonzeroExit = error as? BackendNonzeroExit {
            errorObject["exit_code"] = Int(nonzeroExit.exitCode)

            let stderrPreview = String(
                nonzeroExit.stderr
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(300)
            )
            errorObject["stderr_preview"] = stderrPreview

            if stderrPreview.isEmpty {
                let tail = Diagnostics.stdoutTail(nonzeroExit.stdout)

                if !tail.isEmpty { errorObject["stdout_tail"] = tail }
            }
        }

        await Log.shared.append(
            "shell.error",
            LogPayload(payload),
            level: .error,
            category: category,
            error: errorObject
        )
    }

    // MARK: - Private
    private static func forgeContext() -> [String: Any] {
        LogContext.workflowContext?.asPayload ?? [:]
    }
}
