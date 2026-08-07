//
//  SubprocessProcessGroupTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("SubprocessProcessGroup Tests")
struct SubprocessProcessGroupTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("cancellation tears down grandchild processes too")
    func cancelTearsDownGrandchild() async throws {
        // Given
        let pidFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("forge-gc-\(ProcessInfo.processInfo.globallyUniqueString).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let script = "sleep 30 & echo $! > \(pidFile.path); sleep 30"
        let task = Task<SubprocessResult, Error> {
            try await Subprocess.run(executable: "/bin/sh", args: ["-c", script],
                cwd: nil, envExtra: nil, stdin: "")
        }
        
        var gcPid: pid_t = 0
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(100))
            if let contents = try? String(contentsOf: pidFile, encoding: .utf8),
            let parsed = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)) {
                gcPid = parsed; break
            }
        }

        // Then
        #expect(gcPid > 0, "grandchild pid was never recorded — test setup failed")
        task.cancel()
        try? await Task.sleep(for: .milliseconds(1500))
        let alive = kill(gcPid, 0) == 0
        kill(gcPid, SIGKILL)
        _ = try? await task.value
        #expect(!alive, "grandchild survived parent teardown — orphaned (06-05 residual)")
    }
    
    // MARK: - Private
}
