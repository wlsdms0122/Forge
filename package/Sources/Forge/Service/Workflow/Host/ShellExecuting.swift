//
//  ShellExecuting.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// forge's runtime services, behind seams so host actions unit-test without a
// daemon. The live wiring (Subprocess, agent backends, the dispatcher pool)
// arrives with the engine swap; actions only ever see these protocols.
//
// Cancellation contract for every seam: an implementation MUST terminate its
// underlying resource (kill the process, abort the agent turn, cancel the
// remote run) when its task is cancelled — `withHostDeadline` and the host's
// runaway control both act solely through task cancellation, so a seam that
// ignores it makes timeouts and cancel decorative.
protocol ShellExecuting: Sendable {
    // `env` entries override the implementation's baseline environment; keys
    // not listed keep their baseline values. `stepID` is diagnostic identity for
    // the host's logs, never semantics.
    func run(
        executable: String,
        args: [String],
        cwd: String?,
        env: [String: String],
        stdin: String?,
        stepID: String?
    ) async throws -> ShellRunOutput
}
