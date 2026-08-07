//
//  SubprocessEnvTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("SubprocessEnv Tests")
struct SubprocessEnvTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("the baseline env plants forge bin and prepends it to PATH")
    func baselineInjectsForgeBinAndPrependsPath() {
        // Given
        let env = SubprocessEnv.baseline()

        // Then
        #expect(env["FORGE_BIN"] == SubprocessEnv.executablePath(), "FORGE_BIN equals executablePath")
        let directory = (SubprocessEnv.executablePath() as NSString).deletingLastPathComponent
        let path = try? #require(env["PATH"])
        if !directory.isEmpty {
            #expect(path?.hasPrefix(directory + ":") ?? false, "forge dir prepended to PATH: \(path ?? "nil")")
        }
    }
    
    @Test("the baseline env carries no socket/runtime values — the spawner provides those")
    func baselineHasNoSocketOrRuntime() {
        // Given
        let env = SubprocessEnv.baseline()

        // Then
        #expect(env["FORGE_SOCKET"] == nil)
        #expect(env["FORGE_RUNTIME"] == nil)
    }
    
    @Test("the forge bin path has a single source — same value as the baseline env")
    func forgeBinEnvIsSingleSourceSharedWithBaseline() {
        // Given
        let shared = SubprocessEnv.forgeBinEnv()

        // Then
        #expect(shared["FORGE_BIN"] == SubprocessEnv.executablePath())
        let base = SubprocessEnv.baseline()
        #expect(base["FORGE_BIN"] == shared["FORGE_BIN"], "baseline includes forgeBinEnv")
        #expect(base["PATH"] == shared["PATH"], "same PATH source")
    }
    
    @Test("spec-provided environment variables win over the defaults")
    func specOverrideWinsOverBaseline() {
        // Given
        let baseline = SubprocessEnv.baseline()
        let merged = SubprocessEnv.merge(baseline: baseline, specOverride: ["PATH": "/custom"])

        // Then
        #expect(merged?["PATH"] == "/custom", "spec overrides baseline PATH")
        #expect(merged?["FORGE_BIN"] == baseline["FORGE_BIN"], "un-overridden keys preserved")
    }
    
    // MARK: - Private
}
