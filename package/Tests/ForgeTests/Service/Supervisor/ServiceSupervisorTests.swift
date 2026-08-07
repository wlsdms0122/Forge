//
//  ServiceSupervisorTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("ServiceSupervisor Tests")
final class ServiceSupervisorTests {
    // MARK: - Property
    private let temporaryDirectory: URL
    
    // MARK: - Initializer
    init() throws {
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("forge-supervisor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }
    
    deinit {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    
    // MARK: - Test
    // MARK: - run / shutdown
    @Test("run spawns and shutdown stops")
    func runSpawnsAndShutdownStops() async throws {
        // Given
        let supervisor = makeSupervisor([longRunning("svc", autoSpawn: false)])

        // When
        let started = try await supervisor.run("svc")

        // Then
        #expect(started.state == "running")
        let pid = try #require(started.pid)
        #expect(kill(pid, 0) == 0, "spawned process should be alive")
        let pidFile = temporaryDirectory.appendingPathComponent("services/svc.pid")
        #expect(FileManager.default.fileExists(atPath: pidFile.path))
        let stopped = try await supervisor.shutdown("svc")
        #expect(stopped.state == "stopped")
        #expect(kill(pid, 0) != 0, "process should be dead after shutdown")
        #expect(!FileManager.default.fileExists(atPath: pidFile.path), "pid file must be removed on clean stop")
    }
    
    @Test("Calling run again while already up still yields one process")
    func runIsIdempotent() async throws {
        // Given
        let supervisor = makeSupervisor([longRunning("svc", autoSpawn: false)])

        // When
        let first = try await supervisor.run("svc")
        let second = try await supervisor.run("svc")

        // Then
        #expect(first.pid == second.pid, "second run must not respawn")
        _ = try await supervisor.shutdown("svc")
    }
    
    @Test("A run during shutdown does not create a double spawn")
    func runDuringShutdownDoesNotDoubleSpawn() async throws {
        // Given
        let supervisor = makeSupervisor([longRunning("svc", autoSpawn: false)])

        // When
        let first = try await supervisor.run("svc")

        // Then
        let oldPid = try #require(first.pid)
        async let stopping = supervisor.shutdown("svc")
        try await Task.sleep(for: .milliseconds(30))
        let second = try await supervisor.run("svc")
        _ = try await stopping
        #expect(second.state == "running")
        let newPid = try #require(second.pid)
        #expect(newPid != oldPid, "old process must be gone, new one spawned")
        #expect(kill(oldPid, 0) != 0, "old process must be dead")
        #expect(kill(newPid, 0) == 0, "exactly one live process")
        _ = try await supervisor.shutdown("svc")
        #expect(kill(newPid, 0) != 0)
    }
    
    @Test("An unknown service throws")
    func runUnknownServiceThrows() async throws {
        // Given
        let supervisor = makeSupervisor([])
        do {

        // When
            _ = try await supervisor.run("ghost")

        // Then
            Issue.record("expected ProtocolError")
        } catch is ProtocolError {
        }
    }
    
    // MARK: - crash loop
    @Test("Repeated crashes transition to failed and stop restarting")
    func crashLoopTransitionsToFailed() async throws {
        // Given
        let spec = ServiceConfig(
            name: "crasher",
            command: ["/bin/sh", "-c", "exit 7"],
            autoSpawn: false,
            restart: .init(backoffInitial: .milliseconds(10),
                backoffMax: .milliseconds(20),
                crashLoopLimit: 3,
                stableUptime: .seconds(60))
        )
        let supervisor = makeSupervisor([spec])

        // When
        _ = try await supervisor.run("crasher")
        try await waitForState(supervisor, "crasher", "failed")
        let records = await supervisor.statuses()

        // Then
        let record = try #require(records.first { record in record.name == "crasher" })
        #expect(record.consecutiveCrashes == 3)
        #expect(record.lastExitCode == 7)
        _ = try await supervisor.run("crasher")
        try await waitForState(supervisor, "crasher", "failed")
    }
    
    @Test("A service that crashed once is restarted")
    func crashedServiceRestarts() async throws {
        // Given
        let marker = temporaryDirectory.appendingPathComponent("ran-once").path
        let spec = ServiceConfig(
            name: "flaky",
            command: ["/bin/sh", "-c",
            "if [ -f \(marker) ]; then sleep 60; else touch \(marker); exit 1; fi"],
            autoSpawn: false,
            restart: .init(backoffInitial: .milliseconds(10),
                backoffMax: .milliseconds(20),
                crashLoopLimit: 5,
                stableUptime: .seconds(60))
        )
        let supervisor = makeSupervisor([spec])
        _ = try await supervisor.run("flaky")
        let deadline = Date().addingTimeInterval(5)
        var record: ServiceStatusRecord?
        while Date() < deadline {
            let records = await supervisor.statuses()
            if let result = records.first(where: { record in record.name == "flaky" }),
            result.state == "running", result.consecutiveCrashes == 1 {
                record = result
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        // Then
        #expect(record != nil, "service must be running again after one crash")
        _ = try await supervisor.shutdown("flaky")
    }
    
    // MARK: - boot (auto_spawn + orphan reaping)
    @Test("Boot spawns only auto_spawn services")
    func bootSpawnsAutoSpawnOnly() async throws {
        // Given
        let supervisor = makeSupervisor([
                longRunning("auto", autoSpawn: true),
                longRunning("manual", autoSpawn: false),
        ])

        // When
        await supervisor.boot()
        try await waitForState(supervisor, "auto", "running")
        let records = await supervisor.statuses()

        // Then
        let manual = try #require(records.first { record in record.name == "manual" })
        #expect(manual.state == "stopped")
        await supervisor.stopAll()
    }
    
    @Test("The boot scan reaps leftover orphan processes")
    func bootReapsStaleOrphan() async throws {
        // Given
        let orphan = Process()
        orphan.executableURL = URL(fileURLWithPath: "/bin/sh")
        orphan.arguments = ["-c", "sleep 60"]
        try orphan.run()
        let servicesDir = temporaryDirectory.appendingPathComponent("services")
        try FileManager.default.createDirectory(at: servicesDir, withIntermediateDirectories: true)
        let pidFile = servicesDir.appendingPathComponent("ghost.pid")
        let info = ["svc": "ghost", "pid": Int(orphan.processIdentifier)] as [String: Any]
        try JSONSerialization.data(withJSONObject: info).write(to: pidFile)
        let supervisor = makeSupervisor([])

        // When
        await supervisor.boot()

        // Then
        #expect(!FileManager.default.fileExists(atPath: pidFile.path), "stale pid file must be removed")
        let deadline = Date().addingTimeInterval(2)
        while orphan.isRunning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!orphan.isRunning, "orphan must be reaped on boot")
    }
    
    @Test("If the pid was reused, someone else's process is not touched")
    func bootSkipsPidReusedByAnotherProcess() async throws {
        // Given
        let bystander = Process()
        bystander.executableURL = URL(fileURLWithPath: "/bin/sh")
        bystander.arguments = ["-c", "sleep 60"]
        try bystander.run()
        defer { bystander.terminate() }
        let servicesDir = temporaryDirectory.appendingPathComponent("services")
        try FileManager.default.createDirectory(at: servicesDir, withIntermediateDirectories: true)
        let pidFile = servicesDir.appendingPathComponent("ghost.pid")
        let info: [String: Any] = [
            "svc": "ghost",
            "pid": Int(bystander.processIdentifier),
            "command": ["/nonexistent/other-binary", "--flag-not-in-argv"],
        ]
        try JSONSerialization.data(withJSONObject: info).write(to: pidFile)
        let supervisor = makeSupervisor([])

        // When
        await supervisor.boot()

        // Then
        #expect(bystander.isRunning, "mismatched process must NOT be killed")
        #expect(!FileManager.default.fileExists(atPath: pidFile.path), "stale record must still be removed")
    }
    
    // MARK: - reload
    @Test("Reload stops removed services and starts added ones")
    func reloadStopsRemovedAndStartsAdded() async throws {
        // Given
        let supervisor = makeSupervisor([longRunning("old")])

        // When
        await supervisor.boot()
        try await waitForState(supervisor, "old", "running")
        let oldRecords = await supervisor.statuses()

        // Then
        let oldPid = try #require(oldRecords.first { oldRecord in oldRecord.name == "old" }?.pid)
        let diff = await supervisor.reload([longRunning("new")])
        #expect(diff["removed"] == ["old"])
        #expect(diff["added"] == ["new"])
        #expect(kill(oldPid, 0) != 0, "removed service must be stopped")
        try await waitForState(supervisor, "new", "running")
        let names = await supervisor.statuses().map(\.name)
        #expect(names == ["new"], "removed service must leave the table")
        await supervisor.stopAll()
    }
    
    // MARK: - teardown reaches the whole process tree
    @Test("Shutdown reaps even the service's grandchildren")
    func shutdownReapsServiceGrandchild() async throws {
        // Given
        let pidFile = temporaryDirectory.appendingPathComponent("gc.pid")
        let service = ServiceConfig(
            name: "svc",
            command: ["/bin/sh", "-c", "sleep 60 & echo $! > \(pidFile.path); sleep 60"],
            autoSpawn: false)
        let supervisor = makeSupervisor([service])
        _ = try await supervisor.run("svc")
        var gcPid: pid_t = 0
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(100))
            if let contents = try? String(contentsOf: pidFile, encoding: .utf8),
            let parsed = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)) { gcPid = parsed; break }
        }

        // Then
        #expect(gcPid > 0, "grandchild pid never recorded — setup failed")
        _ = try await supervisor.shutdown("svc")
        try? await Task.sleep(for: .milliseconds(500))
        let alive = kill(gcPid, 0) == 0
        kill(gcPid, SIGKILL)
        #expect(!alive, "service grandchild survived shutdown — orphaned (bare-pid teardown drift)")
    }
    
    // MARK: - Private
    private func makeSupervisor(_ services: [ServiceConfig]) -> ServiceSupervisor {
        ServiceSupervisor(
            services: services,
            runtimeDirectory: temporaryDirectory,
            tokenAuthority: TokenAuthority()
        )
    }
    
    private func longRunning(_ name: String, autoSpawn: Bool = true) -> ServiceConfig {
        ServiceConfig(name: name, command: ["/bin/sh", "-c", "sleep 60"],
            autoSpawn: autoSpawn)
    }
    
    private func waitForState(_ supervisor: ServiceSupervisor, _ name: String,
        _ state: String, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let record = await supervisor.statuses().first(where: { status in status.name == name }),
            record.state == state {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        
        let records = await supervisor.statuses()
        Issue.record("service '\(name)' never reached '\(state)' — statuses: \(records.map { record in (record.name, record.state) })")
    }
}
