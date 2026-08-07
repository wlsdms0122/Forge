//
//  SubprocessCancelTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("SubprocessCancel Tests")
struct SubprocessCancelTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("cancellation before spawn does not leak a child")
    func cancelBeforeSpawnDoesNotLeakChild() async {
        // Given
        let task = Task<SubprocessResult, Error> {
            try await Subprocess.run(executable: "/bin/sleep", args: ["30"],
                cwd: nil, envExtra: nil)
        }
        task.cancel()
        let started = ContinuousClock.now
        _ = try? await task.value
        let elapsed = (ContinuousClock.now - started).milliseconds

        // Then
        #expect(elapsed < 5000, "spawn-window cancellation was lost and the child slept the full 30s")
    }
    
    @Test("the termination signal is sent exactly once")
    func spawnGuardTerminatesExactlyOnce() {
        // Given
        let firstGuard = SpawnGuard()

        // Then
        #expect(!firstGuard.markStarted(), "start before cancel does not terminate")
        #expect(firstGuard.markCancelled(), "if already started, cancel terminates")
        let secondGuard = SpawnGuard()
        #expect(!secondGuard.markCancelled(), "cancel before start does not terminate (flag only)")
        #expect(secondGuard.markStarted(), "if already cancelled, start terminates")
        let thirdGuard = SpawnGuard()
        #expect(!thirdGuard.markStarted(), "without cancellation, no termination")
    }
    
    @Test("without cancellation, it runs to completion normally")
    func noCancelRunsNormally() async throws {
        // Given
        let result = try await Subprocess.run(executable: "/bin/echo", args: ["hi"],
            cwd: nil, envExtra: nil)

        // Then
        #expect(result.exitCode == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hi")
    }
    
    // MARK: - Private
}
