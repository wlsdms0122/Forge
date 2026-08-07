//
//  ConfigLoaderTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("ConfigLoader Tests")
struct ConfigLoaderTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("cfg")

    // MARK: - Initializer
    // MARK: - Test
    @Test("An invalid numeric env var is reported with builtin source, not env")
    func invalidEnvNumericReportsBuiltinNotEnv() throws {
        // Given
        let noToml = "/nonexistent-forge-config-\(UUID().uuidString).toml"
        let home = try temporary.make("home")
        defer { try? FileManager.default.removeItem(at: home) }
        let invalidEnvironment = try ConfigLoader.loadWithSources(configPath: noToml, sessionHome: home,
            environment: ["FORGE_LOG_MAXIMUM_BYTES": "abc"])

        // Then
        let maxBytes = try #require(invalidEnvironment.entries.first { entry in entry.key == "log_maximum_bytes" })
        #expect(maxBytes.source.label == "default", "invalid env falsely reported as source=env")
        #expect(maxBytes.value == String(50 * 1024 * 1024))
        let zeroConcurrency = try ConfigLoader.loadWithSources(configPath: noToml, sessionHome: home,
            environment: ["FORGE_POOL_MAXIMUM_CONCURRENT_STEPS": "0"])
        let zeroed = try #require(zeroConcurrency.entries.first { entry in entry.key == "pool.maximum_concurrent_steps" })
        #expect(zeroed.source.label == "default", "0 fails the >0 gate so builtin applies, yet source=env is falsely reported")
        let validConcurrency = try ConfigLoader.loadWithSources(configPath: noToml, sessionHome: home,
            environment: ["FORGE_POOL_MAXIMUM_CONCURRENT_STEPS": "8"])
        let concurrency = try #require(validConcurrency.entries.first { entry in entry.key == "pool.maximum_concurrent_steps" })
        #expect(concurrency.source.label == "environment (FORGE_POOL_MAXIMUM_CONCURRENT_STEPS)")
        #expect(concurrency.value == "8")
        let runtimeOverride = try ConfigLoader.loadWithSources(configPath: noToml, sessionHome: home,
            environment: ["FORGE_RUNTIME": "/tmp/rt"])
        #expect(runtimeOverride.entries.first { entry in entry.key == "runtime_directory" } == nil)
        #expect(runtimeOverride.entries.first { entry in entry.key == "socket" } == nil)
    }
    
    @Test("An invalid TOML value falls through to the next source, not to 0")
    func invalidTOMLPoolValueFallsThroughNotToZero() throws {
        // Given
        let directory = try temporary.make("poolzero")
        let home = try temporary.make("poolzero-home")
        defer { for d in [directory, home] { try? FileManager.default.removeItem(at: d) } }
        let url = try writeTOML("[pool]\nmaximum_concurrent_steps = 0\n", in: directory)
        let configuration = ConfigLoader.build(file: try ConfigLoader.parse(url), tomlDirectory: directory, sessionHome: home, environment: [:])

        // Then
        #expect(configuration.pool.maximumConcurrentSteps == 4, "an invalid toml value (0) must fall through to the builtin default")
        let report = try ConfigLoader.loadWithSources(configPath: url.path, sessionHome: home, environment: [:])
        let entry = try #require(report.entries.first { entry in entry.key == "pool.maximum_concurrent_steps" })
        #expect(entry.source.label == "default", "invalid toml must not be falsely reported as source=toml")
        #expect(entry.value == "4", "the report value must match the actual build value (4) so daemon.status/workflow.list_active do not diverge")
    }
    
    @Test("With no configuration, convention defaults take effect")
    func conventionDefaultsWhenSilent() throws {
        // Given
        let directory = try temporary.make("conv")
        let home = try temporary.make("home")
        defer { for d in [directory, home] { try? FileManager.default.removeItem(at: d) } }
        let url = try writeTOML("[pool]\nmaximum_concurrent_steps = 2\n", in: directory)
        let configuration = ConfigLoader.build(file: try ConfigLoader.parse(url), tomlDirectory: directory, sessionHome: home, environment: [:])

        // Then
        #expect(configuration.workflowDirectory?.path == home.appendingPathComponent("workflow").path)
        #expect(configuration.scheduleDirectory?.path == home.appendingPathComponent("schedule").path)
        #expect(configuration.resourceDirectory?.path == home.appendingPathComponent("resource").path)
        #expect(configuration.policyDirectory?.path == home.appendingPathComponent("policy").path)
        #expect(configuration.runtimeDirectory.path == home.appendingPathComponent("runtime").path)
        #expect(configuration.logJSONL.path == home.appendingPathComponent("log/forge.log.jsonl").path)
        #expect(configuration.pool.maximumConcurrentSteps == 2)
        #expect(!(configuration.workflowDirectory!.path.hasPrefix(directory.path)), "the catalog must not be tied to the config.toml location")
    }
    
    @Test("[directory] and [log] tables override the session-home defaults")
    func dirAndLogTablesOverride() throws {
        // Given
        let directory = try temporary.make("ovr")
        let home = try temporary.make("home")
        defer { for d in [directory, home] { try? FileManager.default.removeItem(at: d) } }
        let url = try writeTOML("""
        [directory]
        workflow = "./wf"
        policy   = "./pol"

        [log]
        jsonl     = "./logs/f.jsonl"
        error     = "./logs/e.log"
        maximum_bytes = 12345
        """, in: directory)
        let configuration = ConfigLoader.build(file: try ConfigLoader.parse(url), tomlDirectory: directory, sessionHome: home, environment: [:])

        // Then
        #expect(configuration.runtimeDirectory.path == home.appendingPathComponent("runtime").path)
        #expect(configuration.workflowDirectory?.path == directory.appendingPathComponent("wf").path)
        #expect(configuration.policyDirectory?.path == directory.appendingPathComponent("pol").path)
        #expect(configuration.logJSONL.path == directory.appendingPathComponent("logs/f.jsonl").path)
        #expect(configuration.errorLog.path == directory.appendingPathComponent("logs/e.log").path)
        #expect(configuration.scheduleDirectory?.path == home.appendingPathComponent("schedule").path)
        #expect(configuration.logMaximumBytes == 12345)
    }
    
    @Test("[provider.<name>] parses into the provider list — the singular spelling every config uses")
    func providerTableParses() throws {
        // Given
        let directory = try temporary.make("prov")
        let home = try temporary.make("prov-home")
        defer { for d in [directory, home] { try? FileManager.default.removeItem(at: d) } }
        let url = try writeTOML("""
        [provider.claude]
        kind = "claude-cli"
        executable = "/tmp/agent-stub"
        """, in: directory)

        // When
        let configuration = ConfigLoader.build(file: try ConfigLoader.parse(url), tomlDirectory: directory, sessionHome: home, environment: [:])

        // Then — a parsed provider must replace the builtin default, or a stub
        // executable in config silently falls through to the real CLI
        let provider = try #require(configuration.providers.first { provider in provider.name == "claude" })
        #expect(provider.kind == "claude-cli")
        #expect(provider.settings["executable"] == "/tmp/agent-stub")
    }

    @Test("When TOML is silent, environment variables win")
    func envOverrideWhenTOMLSilent() throws {
        // Given
        let directory = try temporary.make("env")
        let home = try temporary.make("home")
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: home) }
        let url = try writeTOML("", in: directory)
        let configuration = ConfigLoader.build(
            file: try ConfigLoader.parse(url), tomlDirectory: directory, sessionHome: home,
            environment: ["FORGE_WORKFLOW_DIRECTORY": "/abs/wf"])

        // Then
        #expect(configuration.workflowDirectory?.path == "/abs/wf")
        #expect(configuration.resourceDirectory?.path == home.appendingPathComponent("resource").path)
    }
    
    // MARK: - Private
    
    private func writeTOML(_ body: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("config.toml")
        try body.write(to: url, atomically: true, encoding: .utf8)
        
        return url
    }
}
