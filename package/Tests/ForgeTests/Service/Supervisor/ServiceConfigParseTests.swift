//
//  ServiceConfigParseTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("ServiceConfigParse Tests")
struct ServiceConfigParseTests {
    @Test("[service.*] blocks are read as service definitions")
    func parseServiceBlocks() throws {
        // Given
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("forge-svc-toml-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let toml = temporaryDirectory.appendingPathComponent("config.toml")
        try """
        [service.slack]
        command    = ["python3", "-m", "slack"]
        working_directory = "./svc"
        log_file   = "./log/slack.log"
        auto_spawn = false
        restart_crash_loop_limit = 9
        environment.PYTHONPATH = "../runtime"

        [service.bare]
        command = ["sleep", "60"]

        [service.tabled.environment]
        A = "1"

        [service.tabled]
        command = ["sleep", "60"]
        """.write(to: toml, atomically: true, encoding: .utf8)
        let directory = URL(fileURLWithPath: temporaryDirectory.path, isDirectory: true)
        let config = ConfigLoader.build(file: try ConfigLoader.parse(toml), tomlDirectory: directory, sessionHome: temporaryDirectory, environment: [:])

        // Then
        #expect(config.services.count == 3)
        let slack = try #require(config.services.first { service in service.name == "slack" })
        #expect(slack.command == ["python3", "-m", "slack"])
        #expect(slack.workingDirectory?.path == temporaryDirectory.appendingPathComponent("svc").path)
        #expect(slack.logFile?.path == temporaryDirectory.appendingPathComponent("log/slack.log").path)
        #expect(!slack.autoSpawn)
        #expect(slack.restart.crashLoopLimit == 9)
        #expect(slack.environment == ["PYTHONPATH": "../runtime"])
        let bare = try #require(config.services.first { service in service.name == "bare" })
        #expect(bare.autoSpawn, "auto_spawn defaults to true")
        #expect(bare.restart.crashLoopLimit == 5, "builtin default")
        #expect(bare.workingDirectory == nil)
        let tabled = try #require(config.services.first { service in service.name == "tabled" })
        #expect(tabled.environment == ["A": "1"])
    }
    
    @Test("A relative command path resolves against the directory containing the toml")
    func relativeCommandPathResolvesAgainstTomlDir() throws {
        // Given
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("forge-svc-toml-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let toml = temporaryDirectory.appendingPathComponent("config.toml")
        try """
        [service.venv]
        command = ["../venv/bin/python", "-m", "svc"]
        """.write(to: toml, atomically: true, encoding: .utf8)
        let directory = URL(fileURLWithPath: temporaryDirectory.path, isDirectory: true)
        let config = ConfigLoader.build(file: try ConfigLoader.parse(toml), tomlDirectory: directory, sessionHome: temporaryDirectory, environment: [:])

        // Then
        let service = try #require(config.services.first)
        #expect(service.command[0] == temporaryDirectory.deletingLastPathComponent().appendingPathComponent("venv/bin/python").path, "path-like relative command must anchor to the toml dir, not the service cwd")
        #expect(Array(service.command.dropFirst()) == ["-m", "svc"])
    }
    
    @Test("A service without a command is skipped")
    func serviceWithoutCommandIsSkipped() throws {
        // Given
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("forge-svc-toml-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let toml = temporaryDirectory.appendingPathComponent("config.toml")
        try """
        [service.broken]
        working_directory = "./svc"
        """.write(to: toml, atomically: true, encoding: .utf8)

        // When
        let config = try ConfigLoader.load(configPath: toml.path, sessionHome: temporaryDirectory)

        // Then
        #expect(config.services.isEmpty)
    }
}
