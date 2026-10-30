//
//  ShellExecuting.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// The shell seam: actions run a process through it, so effects unit-test
// without a daemon.
//
// An implementation MUST kill its process when its task is cancelled:
// `Deadline` and forge's runaway control act solely through task
// cancellation, so a seam that ignores it makes timeouts and cancel
// decorative.
protocol ShellExecuting: Sendable {
    // `env` entries override the implementation's baseline environment; keys
    // not listed keep their baseline values. `stepID` is diagnostic identity for
    // forge's logs, never semantics.
    func run(
        executable: String,
        args: [String],
        cwd: String?,
        env: [String: String],
        stdin: String?,
        stepID: String?
    ) async throws -> ShellRunOutput
}
