//
//  ScheduleStoreRuntimeTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

/// Schedules created and deleted at runtime — do they stay separate from config-owned ones?
@Suite("ScheduleStoreRuntime Tests")
struct ScheduleStoreRuntimeTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("schedule-runtime")

    // MARK: - Initializer
    // MARK: - Test
    // MARK: - runtime create / delete
    @Test("Runtime create writes to the runtime directory")
    func createWritesToRuntimeDir() async throws {
        // Given
        let directory = try temporary.make("create-d")
        let runtimeDirectoryectory = try temporary.make("create-e")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: runtimeDirectoryectory)
        }
        
        let store = ScheduleStore(configDir: directory, runtimeDirectory: runtimeDirectoryectory, stateFile: try temporary.file("schedule-enabled.json"))
        let schedule = Schedule(id: "watch-1", workflow: "slack-watch",
            trigger: .every(Interval(seconds: 600)))

        // When
        let created = try await store.create(schedule)

        // Then
        #expect(FileManager.default.fileExists(
                atPath: runtimeDirectoryectory.appendingPathComponent("\(created.id).yaml").path))
        #expect(ScheduleIDSpace.isRuntime(created.id), "create must stamp the runtime partition — got '\(created.id)'")
        let entries = await store.catalog().entries
        guard let error = entries.first(where: { entry in entry.schedule.id == created.id }) else {
            Issue.record("created schedule not found")
            
            return
        }
        
        #expect(error.runtime)
        #expect(error.schedule.enabled, "create must seed the enabled ledger so it is born enabled")
    }

    @Test("Create rejects a duplicate id")
    func createRejectsDuplicateId() async throws {
        // Given
        let directory = try temporary.make("dup-d")
        let runtimeDirectoryectory = try temporary.make("dup-e")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: runtimeDirectoryectory)
        }
        
        let store = ScheduleStore(configDir: directory, runtimeDirectory: runtimeDirectoryectory, stateFile: try temporary.file("schedule-enabled.json"))
        let schedule = Schedule(id: "dup", workflow: "wf", trigger: .every(Interval(seconds: 60)))
        try await store.create(schedule)
        do {

        // When
            try await store.create(schedule)

        // Then
            Issue.record("duplicate id must throw")
        } catch {  }
    }

    @Test("Does not create with an already-colliding id")
    func createRejectsCollidedId() async throws {
        // Given
        let configDir = try temporary.make("colcr-cfg")
        let runtimeDirectory = try temporary.make("colcr-rt")
        defer {
            try? FileManager.default.removeItem(at: configDir)
            try? FileManager.default.removeItem(at: runtimeDirectory)
        }
        for sub in ["x", "y"] {
            try FileManager.default.createDirectory(
                at: runtimeDirectory.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        
        let stamped = ScheduleIDSpace.stamp("dup")
        let runtimeYAML = #"""
        workflow: b
        every: 2h
        """#
        let runtimeFile = runtimeDirectory.appendingPathComponent("x/\(stamped).yaml")
        try runtimeYAML.write(to: runtimeFile, atomically: true, encoding: .utf8)
        try runtimeYAML.write(to: runtimeDirectory.appendingPathComponent("y/\(stamped).yaml"),
            atomically: true, encoding: .utf8)
        let store = ScheduleStore(configDir: configDir, runtimeDirectory: runtimeDirectory, stateFile: try temporary.file("schedule-enabled.json"))
        do {
            try await store.create(Schedule(id: "dup", workflow: "c",
                    trigger: .every(Interval(seconds: 60))))

        // Then
            Issue.record("create with a collided id must throw — collided ≠ absent")
        } catch {  }
        #expect(try String(contentsOf: runtimeFile, encoding: .utf8) == runtimeYAML, "existing runtime definition must not be clobbered by create")
    }

    @Test("Does not clobber a foreign definition file")
    func createDoesNotClobberForeignDeclarationFile() async throws {
        // Given
        let configDir = try temporary.make("clob-cfg")
        let runtimeDirectory = try temporary.make("clob-rt")
        defer {
            try? FileManager.default.removeItem(at: configDir)
            try? FileManager.default.removeItem(at: runtimeDirectory)
        }
        
        let foreignYAML = #"""
        id: other
        workflow: wf
        every: 1h
        """#
        let destFile = runtimeDirectory.appendingPathComponent(
            "\(ScheduleIDSpace.stamp("target")).yaml")
        try foreignYAML.write(to: destFile, atomically: true, encoding: .utf8)
        let store = ScheduleStore(configDir: configDir, runtimeDirectory: runtimeDirectory, stateFile: try temporary.file("schedule-enabled.json"))
        do {
            try await store.create(Schedule(id: "target", workflow: "wf",
                    trigger: .every(Interval(seconds: 60))))

        // Then
            Issue.record("must throw when the destination filename is already declaring — never clobber someone else's file")
        } catch {  }
        #expect(try String(contentsOf: destFile, encoding: .utf8) == foreignYAML, "existing declaration file must not be clobbered by create")
        let other = await store.lookup("other")
        #expect(other == nil, "a declaration whose id and filename disagree is not accepted as live")
        let failures = await store.catalog().failures
        #expect(failures.contains { failure in failure.reason.contains("basename") }, "the mismatch must be loud via failures — got: \(failures.map(\.reason))")
    }

    @Test("A broken file blocks only its own id")
    func brokenFileBlocksOnlyItsOwnID() async throws {
        // Given
        let configDir = try temporary.make("unk-cfg")
        let runtimeDirectory = try temporary.make("unk-rt")
        defer {
            try? FileManager.default.removeItem(at: configDir)
            try? FileManager.default.removeItem(at: runtimeDirectory)
        }
        try "id: [broken".write(
            to: runtimeDirectory.appendingPathComponent(
                "\(ScheduleIDSpace.stamp("broken")).yaml"),
            atomically: true, encoding: .utf8)
        let store = ScheduleStore(configDir: configDir, runtimeDirectory: runtimeDirectory, stateFile: try temporary.file("schedule-enabled.json"))
        do {
            try await store.create(Schedule(id: "broken", workflow: "wf",
                    trigger: .every(Interval(seconds: 60))))

        // Then
            Issue.record("an id declared by a broken file cannot be proven absent — must throw")
        } catch {  }
        let created = try await store.create(Schedule(id: "fresh", workflow: "wf",
                trigger: .every(Interval(seconds: 60))))
        let fresh = await store.lookup(created.id)
        #expect(fresh != nil, "an unrelated file's load failure must not block create for another id")
    }

    @Test("Mutating a collided id surfaces the collision")
    func mutationOnCollidedIdSurfacesCollision() async throws {
        // Given
        let configDir = try temporary.make("colmut-cfg")
        let runtimeDirectory = try temporary.make("colmut-rt")
        let state = configDir.appendingPathComponent("state.json")
        defer {
            try? FileManager.default.removeItem(at: configDir)
            try? FileManager.default.removeItem(at: runtimeDirectory)
        }
        for (sub, wf) in [("a", "a"), ("b", "b")] {
            let directory = configDir.appendingPathComponent(sub)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try """
            id: dup
            workflow: \(wf)
            every: 1h
            """.write(to: directory.appendingPathComponent("dup.yaml"), atomically: true, encoding: .utf8)
        }
        
        let store = ScheduleStore(configDir: configDir, runtimeDirectory: runtimeDirectory, stateFile: state)
        do {

        // When
            try await store.delete(id: "dup", authorizedWorkflow: "a")

        // Then
            Issue.record("delete on a collided id must throw")
        } catch {
            #expect("\(error)".contains("collid"), "the error must mention the collision — got: \(error)")
        }
        do {
            try await store.setEnabled(id: "dup", enabled: false, authorizedWorkflow: "a")
            Issue.record("setEnabled on a collided id must throw")
        } catch {
            #expect("\(error)".contains("collid"), "the error must mention the collision — got: \(error)")
        }
    }

    @Test("Create is rejected when there is no runtime directory")
    func createRejectsWhenNoRuntimeDir() async throws {
        // Given
        let directory = try temporary.make("noeph")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScheduleStore(configDir: directory, runtimeDirectory: nil, stateFile: try temporary.file("schedule-enabled.json"))
        do {
            try await store.create(Schedule(id: "x", workflow: "wf",
                    trigger: .every(Interval(seconds: 60))))

        // Then
            Issue.record("must throw when there is no runtime schedule dir")
        } catch {  }
    }

    @Test("An id starting with a dot is not safe")
    func storeSafeIDRejectsLeadingDot() {
        #expect(!isStoreSafeID(".hidden"), "a leading dot makes the file hidden, unreadable on reload, so it is rejected")
        #expect(!isStoreSafeID("."))
        #expect(!isStoreSafeID(".."))
        #expect(!isStoreSafeID(""))
        #expect(isStoreSafeID("v1.2"), "an interior dot is allowed")
        #expect(isStoreSafeID("my-job_1"))
    }

    @Test("Create rejects an id starting with a dot")
    func createRejectsLeadingDotID() async throws {
        // Given
        let directory = try temporary.make("dot-d")
        let runtimeDirectoryectory = try temporary.make("dot-e")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: runtimeDirectoryectory)
        }
        
        let store = ScheduleStore(configDir: directory, runtimeDirectory: runtimeDirectoryectory, stateFile: try temporary.file("schedule-enabled.json"))
        do {
            try await store.create(Schedule(id: ".hidden", workflow: "wf",
                    trigger: .every(Interval(seconds: 60))))

        // Then
            Issue.record("a leading-dot id must be rejected")
        } catch {  }
        #expect(!FileManager.default.fileExists(atPath: runtimeDirectoryectory.appendingPathComponent(".hidden.yaml").path), "rejected, yet an orphan file was left behind")
    }

    @Test("Delete a runtime-owned entry")
    func deleteRuntime() async throws {
        // Given
        let directory = try temporary.make("del-d")
        let runtimeDirectoryectory = try temporary.make("del-e")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: runtimeDirectoryectory)
        }
        
        let store = ScheduleStore(configDir: directory, runtimeDirectory: runtimeDirectoryectory, stateFile: try temporary.file("schedule-enabled.json"))
        let created = try await store.create(Schedule(id: "tmp", workflow: "wf",
                trigger: .every(Interval(seconds: 60))))

        // When
        let before = await store.lookup(created.id)

        // Then
        #expect(before != nil)
        try await store.delete(id: created.id)
        let after = await store.lookup(created.id)
        #expect(after == nil)
        #expect(!FileManager.default.fileExists(
                atPath: runtimeDirectoryectory.appendingPathComponent("\(created.id).yaml").path))
    }

    @Test("Config-owned entries are deleted too")
    func deleteWorksOnConfig() async throws {
        // Given
        let directory = try temporary.make("deldur-d")
        let runtimeDirectoryectory = try temporary.make("deldur-e")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: runtimeDirectoryectory)
        }
        try #"""
        id: config
        workflow: wf
        every: 1h
        """#.write(to: directory.appendingPathComponent("config.yaml"),
            atomically: true, encoding: .utf8)
        let store = ScheduleStore(configDir: directory, runtimeDirectory: runtimeDirectoryectory, stateFile: try temporary.file("schedule-enabled.json"))

        // When
        try await store.delete(id: "config")
        let gone = await store.lookup("config")

        // Then
        #expect(gone == nil, "config-owned entry must be deleted too")
        #expect(!FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("config.yaml").path))
    }

    @Test("Runtime directory nested inside config is not double-counted")
    func runtimeDirectoryNestedNotDoubleCounted() async throws {
        // Given
        let directory = try temporary.make("nested")
        let runtimeDirectoryectory = directory.appendingPathComponent("agent-runtime")
        try FileManager.default.createDirectory(at: runtimeDirectoryectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScheduleStore(configDir: directory, runtimeDirectory: runtimeDirectoryectory, stateFile: try temporary.file("schedule-enabled.json"))
        let created = try await store.create(Schedule(id: "nested-1", workflow: "wf",
                trigger: .every(Interval(seconds: 60))))
        let entries = await store.catalog().entries
        let matches = entries.filter { entry in entry.schedule.id == created.id }

        // Then
        #expect(matches.count == 1, "must be counted only once")
        #expect(matches.first?.runtime ?? false)
    }

    @Test("A hand-edited spec claiming a foreign name is rejected")
    func handEditedForeignSpecNameRejected() async throws {
        // Given
        let directory = try temporary.make("cfg-foreign"); defer { try? FileManager.default.removeItem(at: directory) }
        let runtimeDirectoryectory = try temporary.make("rt-foreign"); defer { try? FileManager.default.removeItem(at: runtimeDirectoryectory) }
        try #"""
        id: he
        workflow: wf-x
        every: 1m
        spec:
          name: evil-identity
          steps: []
        """#.write(to: directory.appendingPathComponent("he.yaml"), atomically: true, encoding: .utf8)
        try #"""
        id: ok
        workflow: wf-y
        every: 1m
        """#.write(to: directory.appendingPathComponent("ok.yaml"), atomically: true, encoding: .utf8)
        let store = ScheduleStore(configDir: directory, runtimeDirectory: runtimeDirectoryectory, stateFile: try temporary.file("schedule-enabled.json"))

        // When
        let control = await store.lookup("ok")

        // Then
        #expect(control != nil, "the control (a valid schedule) must load")
        let loaded = await store.lookup("he")
        #expect(loaded == nil, "a hand-edited schedule whose spec carries a self-claimed name must be rejected at the load boundary")
    }

    @Test("A hand-written anonymous spec receives a sigil")
    func handEditedAnonymousSpecGetsSigil() async throws {
        // Given
        let directory = try temporary.make("cfg-anon"); defer { try? FileManager.default.removeItem(at: directory) }
        let runtimeDirectoryectory = try temporary.make("rt-anon"); defer { try? FileManager.default.removeItem(at: runtimeDirectoryectory) }
        try #"""
        id: ha
        workflow: wf-x
        every: 1m
        spec:
          steps: []
        """#.write(to: directory.appendingPathComponent("ha.yaml"), atomically: true, encoding: .utf8)
        let store = ScheduleStore(configDir: directory, runtimeDirectory: runtimeDirectoryectory, stateFile: try temporary.file("schedule-enabled.json"))

        // When
        let fetched = await store.lookup("ha")

        // Then
        let schedule = try #require(fetched, "anonymous spec must load")
        guard case .object(let object)? = schedule.spec else {
            Issue.record("spec must be an object")
            
            return
        }
        
        #expect(object["name"] == .string("<inline>"), "sigil must be injected into the anonymous spec")
    }

    @Test("A broken file and an id collision both surface as failures, and the collided id is excluded on both sides")
    func surfacesDecodeFailureAndCollision() async throws {
        // Given
        let directory = try temporary.make("decode-collision")
        try "id: [broken".write(
            to: directory.appendingPathComponent("broken.yaml"), atomically: true, encoding: .utf8)

        for sub in ["a", "b"] {
            let subdirectory = directory.appendingPathComponent(sub)
            try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
            try "id: dup\nworkflow: w\nevery: 1h\n".write(
                to: subdirectory.appendingPathComponent("dup.yaml"), atomically: true, encoding: .utf8)
        }

        let store = ScheduleStore(
            configDir: directory,
            stateFile: try temporary.file("enabled-\(UUID().uuidString.prefix(6)).json"))

        // When
        let catalog = await store.catalog()

        // Then
        #expect(catalog.failures.contains { failure in failure.path == "broken.yaml" }, "decode failure must surface")
        #expect(
            catalog.failures.filter { failure in failure.reason.contains("collides") }.count == 2,
            "both sides of the collision surface as failures")
        #expect(catalog.entries.isEmpty, "collided id is excluded from live on both sides")
    }
    // MARK: - Private
}
