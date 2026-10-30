//
//  LiveShellTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
import Warp
@testable import Forge

@Suite("LiveShell Tests")
struct LiveShellTests {
    // MARK: - Property
    private let sut = LiveShell()

    // MARK: - Initializer
    // MARK: - Test
    @Test("runs a process and returns its exit code and stdout")
    func runReturnsExitAndStdoutOnSuccess() async throws {
        // When
        let output = try await sut.run(
            executable: "/bin/echo",
            args: ["hello"],
            cwd: nil,
            env: [:],
            stdin: nil,
            stepID: nil
        )

        // Then
        #expect(output.exitCode == 0)
        #expect(output.stdout == "hello\n")
    }

    @Test("env is overlaid on top of the baseline")
    func envOverridesBaseline() async throws {
        // When
        let output = try await sut.run(
            executable: "/bin/sh",
            args: ["-c", "printf %s \"$LIVE_SEAM_PROBE\""],
            cwd: nil,
            env: ["LIVE_SEAM_PROBE": "seam-value"],
            stdin: nil,
            stepID: nil
        )

        // Then
        #expect(output.stdout == "seam-value")
    }

    @Test("nonzero exit is returned as-is, without judgment — judging is the action's job")
    func runReportsNonzeroExitCode() async throws {
        // When
        let output = try await sut.run(
            executable: "/bin/sh",
            args: ["-c", "echo oops >&2; exit 3"],
            cwd: nil,
            env: [:],
            stdin: nil,
            stepID: nil
        )

        // Then
        #expect(output.exitCode == 3)
        #expect(output.stderr.contains("oops"))
    }

    @Test("task cancellation kills the process — the seam's cancellation contract")
    func cancellationKillsProcess() async throws {
        // Given
        let sut = self.sut
        let started = ContinuousClock.now
        let task = Task {
            try await sut.run(
                executable: "/bin/sleep",
                args: ["10"],
                cwd: nil,
                env: [:],
                stdin: nil,
                stepID: nil
            )
        }

        // When
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()

        let result = await task.result

        // Then
        // The essence of the contract is "the process dies and we return quickly" — the kill
        // may surface as a throw (cancelled before spawn) or as a signal-terminated nonzero exit.
        let elapsed = ContinuousClock.now - started
        let survivedWithZeroExit = (try? result.get())?.exitCode == 0

        #expect(!survivedWithZeroExit, "a cancelled process must not survive to completion")
        #expect(elapsed < .seconds(8), "after cancellation, must return quickly without waiting for process exit")
    }
}
