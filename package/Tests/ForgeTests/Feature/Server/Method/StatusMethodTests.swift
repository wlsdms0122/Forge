//
//  StatusMethodTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("StatusMethod Tests")
struct StatusMethodTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("status")

    // MARK: - Initializer
    // MARK: - Test
    @Test("reports all three axes together: daemon, config, and runtime")
    func reportsDaemonConfigAndRuntime() async throws {
        // Given
        let home = try temporary.make("ok"); defer { try? FileManager.default.removeItem(at: home) }
        let socket = home.appendingPathComponent("forged.sock").path
        let (method, authority) = makeMethod(home, socket: socket)
        let token = authority.mint(TokenClaims(principal: "system:admin"))

        // When
        let result = try await method.handle(request(["token": token])).dict

        // Then
        let daemon = try #require(result["daemon"] as? [String: Any])
        #expect(daemon["session"] as? String == "test")
        #expect(daemon["socket"] as? String == socket)
        #expect(daemon["pid"] != nil)
        let config = try #require(result["config"] as? [String: Any])
        let values = try #require(config["values"] as? [[String: Any]])
        let socketEntry = try #require(values.first { value in (value["key"] as? String) == "socket" })
        #expect(socketEntry["value"] as? String == socket)
        #expect(socketEntry["source"] as? String == "session")
        let runtimeEntry = try #require(values.first { value in (value["key"] as? String) == "runtime_directory" })
        #expect(runtimeEntry["value"] as? String == home.appendingPathComponent("runtime").path)
        #expect(runtimeEntry["source"] as? String == "session")
        let runtime = try #require(result["runtime"] as? [String: Any])
        #expect(runtime["workflows"] as? Int == 0)
        #expect(runtime["jobs"] as? Int == 0)
    }
    
    @Test("status queries stay open even without a token")
    func worksWithoutToken() async throws {
        // Given
        let home = try temporary.make("notok"); defer { try? FileManager.default.removeItem(at: home) }
        let (method, _) = makeMethod(home, socket: home.appendingPathComponent("forged.sock").path)

        // When
        let result = try await method.handle(request([:])).dict

        // Then
        #expect(result["daemon"] != nil, "daemon section returned even without a token")
    }
    
    @Test("answers with the boot snapshot — values do not evaporate even if the toml is broken at response time")
    func reportsBootSnapshotNotDisk() async throws {
        // Given
        let home = try temporary.make("snapshot-home")
        let configURL = try temporary.write("[pool]\nmaximum_concurrent_steps = 7\n", to: "config.toml")
        let (_, report) = try ConfigLoader.loadResolved(
            configPath: configURL.path, sessionHome: home, environment: [:])
        let authority = TokenAuthority()
        let method = DaemonStatusMethod(
            session: "test",
            socketPath: "/tmp/s.sock",
            runtimeDirectory: home.appendingPathComponent("runtime"),
            bootedAt: .fixture,
            configSnapshot: ConfigSnapshot(report),
            workflowStore: SpecCatalog(directory: nil, loader: ForgeSpec.loader()),
            scheduleStore: ScheduleStore(
                configDir: nil,
                runtimeDirectory: nil,
                stateFile: try temporary.file("enabled-\(UUID().uuidString.prefix(6)).json")),
            jobStore: JobStore(directory: nil),
            supervisor: ServiceSupervisor(services: [], runtimeDirectory: home, tokenAuthority: authority),
            handlerBus: WorkflowHandlerBus())

        // When
        try "not [valid toml".write(to: configURL, atomically: true, encoding: .utf8)
        let output = try await method.handle(request([:]))

        // Then
        let config = try #require(output.dict["config"] as? [String: Any])
        let values = try #require(config["values"] as? [[String: Any]])
        let pool = try #require(
            values.first { value in (value["key"] as? String) == "pool.maximum_concurrent_steps" })
        #expect(pool["value"] as? String == "7", "must be the boot snapshot value — re-parsing from disk would lose it to the corrupted toml")
    }

    // MARK: - Private
    
    private func makeMethod(_ home: URL, socket: String) -> (DaemonStatusMethod, TokenAuthority) {
        let authority = TokenAuthority()
        let method = DaemonStatusMethod(
            session: "test", socketPath: socket, runtimeDirectory: home.appendingPathComponent("runtime"),
            bootedAt: .fixture,
            configSnapshot: ConfigSnapshot((try? ConfigLoader.loadResolved(configPath: nil, sessionHome: home, environment: [:]).report)
                ?? ConfigReport(tomlPath: nil, entries: [])),
            workflowStore: SpecCatalog(directory: nil, loader: ForgeSpec.loader()),
            scheduleStore: ScheduleStore(configDir: nil, runtimeDirectory: nil, stateFile: FileManager.default.temporaryDirectory.appendingPathComponent("forge-sched-enabled-\(UUID().uuidString.prefix(6)).json")),
            jobStore: JobStore(directory: nil),
            supervisor: ServiceSupervisor(services: [], runtimeDirectory: home, tokenAuthority: authority),
            handlerBus: WorkflowHandlerBus())
        
        return (method, authority)
    }
    
    private func request(_ params: [String: Any]) -> RPCRequest {
        RPCRequest(id: "r-\(UUID().uuidString.prefix(6))", method: "daemon.status", params: params)
    }
}
