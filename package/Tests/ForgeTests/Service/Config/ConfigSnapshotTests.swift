//
//  ConfigSnapshotTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import Forge

@Suite("ConfigSnapshot Tests")
struct ConfigSnapshotTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("Reload swaps only the service entries and keeps the boot values for the rest")
    func updateServicesReplacesOnlyServiceEntries() async {
        // Given
        let boot = ConfigReport(tomlPath: "/a.toml", entries: [
                .init(key: "pool.maximum_concurrent_steps", value: "4", source: .builtin),
                .init(key: "service.slack", value: "old-cmd", source: .toml),
        ])
        let snapshot = ConfigSnapshot(boot)
        let reloaded = ConfigReport(tomlPath: "/a.toml", entries: [
                .init(key: "pool.maximum_concurrent_steps", value: "9", source: .toml),
                .init(key: "service.slack", value: "new-cmd", source: .toml),
                .init(key: "service.jira", value: "added", source: .toml),
        ])

        // When
        await snapshot.updateServices(from: reloaded)

        // Then
        let current = await snapshot.current()
        #expect(
            current.entries.first { entry in entry.key == "pool.maximum_concurrent_steps" }?.value == "4",
            "reload reapplies services only — pool keeps the boot value")
        #expect(current.entries.first { entry in entry.key == "service.slack" }?.value == "new-cmd")
        #expect(current.entries.first { entry in entry.key == "service.jira" }?.value == "added")
    }
}
