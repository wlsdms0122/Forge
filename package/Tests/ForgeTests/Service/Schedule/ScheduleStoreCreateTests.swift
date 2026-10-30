//
//  ScheduleStoreCreateTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

// Schedules created and deleted through the store, beside files written into its directory.
@Suite("ScheduleStoreCreate Tests")
struct ScheduleStoreCreateTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("schedule-create")

    // MARK: - Initializer
    // MARK: - Test
    // MARK: - create / delete
    @Test("Create writes the requested id as is into the schedule directory")
    func createWritesRequestedIDIntoDirectory() async throws {
        // Given
        let directory = try temporary.make("create")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sut = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))
        let schedule = Schedule(id: "watch-1", workflow: "slack-watch",
            trigger: .every(Interval(seconds: 600)))

        // When
        let created = try await sut.create(schedule)

        // Then
        #expect(created.id == "watch-1", "create keeps the requested id without any prefix")
        #expect(FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("watch-1.yaml").path))
        let entries = await sut.reload().entries
        let entry = try #require(entries.first { entry in entry.schedule.id == "watch-1" }, "created schedule not found")
        #expect(entry.schedule.enabled, "create must seed the enabled ledger so it is born enabled")
    }

    @Test("Create rejects a duplicate id")
    func createRejectsDuplicateId() async throws {
        // Given
        let directory = try temporary.make("dup")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sut = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))
        let schedule = Schedule(id: "dup", workflow: "wf", trigger: .every(Interval(seconds: 60)))
        try await sut.create(schedule)

        // When
        let error = await failure { try await sut.create(schedule) }

        // Then
        #expect(error != nil, "duplicate id must throw")
    }

    @Test("Create rejects an id a file written into the directory already holds")
    func createRejectsIDOfWrittenFile() async throws {
        // Given
        let directory = try temporary.make("written")
        defer { try? FileManager.default.removeItem(at: directory) }
        let yaml = #"""
        workflow: wf
        every: 1h
        """#
        let file = directory.appendingPathComponent("taken.yaml")
        try yaml.write(to: file, atomically: true, encoding: .utf8)
        let sut = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let error = await failure {
            try await sut.create(Schedule(id: "taken", workflow: "other",
                    trigger: .every(Interval(seconds: 60))))
        }

        // Then
        #expect(error != nil, "an id held by a file in the directory is not free")
        #expect(try String(contentsOf: file, encoding: .utf8) == yaml, "the existing file must not be clobbered by create")
    }

    @Test("Does not clobber a foreign definition file")
    func createDoesNotClobberForeignDeclarationFile() async throws {
        // Given
        let directory = try temporary.make("clob")
        defer { try? FileManager.default.removeItem(at: directory) }
        let foreignYAML = #"""
        id: other
        workflow: wf
        every: 1h
        """#
        let destFile = directory.appendingPathComponent("target.yaml")
        try foreignYAML.write(to: destFile, atomically: true, encoding: .utf8)
        let sut = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let error = await failure {
            try await sut.create(Schedule(id: "target", workflow: "wf",
                    trigger: .every(Interval(seconds: 60))))
        }

        // Then
        #expect(error != nil, "must throw when the destination file already declares something; never clobber someone else's file")
        #expect(try String(contentsOf: destFile, encoding: .utf8) == foreignYAML, "existing declaration file must not be clobbered by create")
        let other = await sut.lookup("other")
        #expect(other == nil, "a declaration whose id and path disagree is not accepted as live")
        let failures = await sut.reload().failures
        #expect(failures.contains { failure in failure.reason.contains("must equal the file's path") }, "the mismatch must be loud via failures, got: \(failures.map(\.reason))")
    }

    @Test("A broken file blocks only its own id")
    func brokenFileBlocksOnlyItsOwnID() async throws {
        // Given
        let directory = try temporary.make("unk")
        defer { try? FileManager.default.removeItem(at: directory) }
        try "id: [broken".write(
            to: directory.appendingPathComponent("broken.yaml"),
            atomically: true, encoding: .utf8)
        let sut = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let blocked = await failure {
            try await sut.create(Schedule(id: "broken", workflow: "wf",
                    trigger: .every(Interval(seconds: 60))))
        }
        let created = try await sut.create(Schedule(id: "fresh", workflow: "wf",
                trigger: .every(Interval(seconds: 60))))

        // Then
        #expect(blocked != nil, "an id declared by a broken file cannot be proven absent")
        let fresh = await sut.lookup(created.id)
        #expect(fresh != nil, "an unrelated file's load failure must not block create for another id")
    }

    @Test("Create rejects an id starting with a dot")
    func createRejectsLeadingDotID() async throws {
        // Given
        let directory = try temporary.make("dot")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sut = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let error = await failure {
            try await sut.create(Schedule(id: ".hidden", workflow: "wf",
                    trigger: .every(Interval(seconds: 60))))
        }

        // Then
        #expect(error != nil, "a leading-dot id must be rejected")
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(".hidden.yaml").path), "rejected, yet an orphan file was left behind")
    }

    @Test("Delete removes a created schedule and its file")
    func deleteRemovesCreatedSchedule() async throws {
        // Given
        let directory = try temporary.make("del")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sut = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))
        let created = try await sut.create(Schedule(id: "tmp", workflow: "wf",
                trigger: .every(Interval(seconds: 60))))
        let before = await sut.lookup(created.id)

        // When
        try await sut.delete(id: created.id)

        // Then
        #expect(before != nil)
        let after = await sut.lookup(created.id)
        #expect(after == nil)
        #expect(!FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("\(created.id).yaml").path))
    }

    @Test("Delete removes a schedule written as a file")
    func deleteRemovesWrittenFile() async throws {
        // Given
        let directory = try temporary.make("del-file")
        defer { try? FileManager.default.removeItem(at: directory) }
        try #"""
        id: written
        workflow: wf
        every: 1h
        """#.write(to: directory.appendingPathComponent("written.yaml"),
            atomically: true, encoding: .utf8)
        let sut = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        try await sut.delete(id: "written")

        // Then
        let gone = await sut.lookup("written")
        #expect(gone == nil, "a schedule written as a file is deleted like a created one")
        #expect(!FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("written.yaml").path))
    }

    @Test("A hand-written schedule naming a workflow and a spec both is refused at the load")
    func handEditedWorkflowAndSpecRefused() async throws {
        // Given
        let directory = try temporary.make("foreign"); defer { try? FileManager.default.removeItem(at: directory) }
        try #"""
        id: he
        workflow: wf-x
        every: 1m
        spec: {}
        """#.write(to: directory.appendingPathComponent("he.yaml"), atomically: true, encoding: .utf8)
        try #"""
        id: ok
        workflow: wf-y
        every: 1m
        """#.write(to: directory.appendingPathComponent("ok.yaml"), atomically: true, encoding: .utf8)
        let sut = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let control = await sut.lookup("ok")

        // Then
        #expect(control != nil, "the control (a valid schedule) must load")
        let loaded = await sut.lookup("he")
        #expect(loaded == nil, "a schedule runs a workflow by name or a spec, so a file writing both is refused")
    }

    @Test("A hand-written spec is kept as written and runs as the inline sigil")
    func handEditedAnonymousSpecIsKeptAsWritten() async throws {
        // Given
        let directory = try temporary.make("anon"); defer { try? FileManager.default.removeItem(at: directory) }
        try #"""
        id: ha
        every: 1m
        spec: {}
        """#.write(to: directory.appendingPathComponent("ha.yaml"), atomically: true, encoding: .utf8)
        let sut = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let fetched = await sut.lookup("ha")

        // Then
        let schedule = try #require(fetched, "a spec must load")
        let spec = try #require(schedule.spec)

        #expect(spec == [:])
        #expect(schedule.workflow == WorkflowCatalog.inlineSigil)
        _ = try await WorkflowCatalog(directory: nil).inline(spec)
    }

    @Test("A broken file surfaces as a failure while the other files load")
    func surfacesDecodeFailureBesideLoadedFiles() async throws {
        // Given
        let directory = try temporary.make("decode")
        defer { try? FileManager.default.removeItem(at: directory) }
        try "id: [broken".write(
            to: directory.appendingPathComponent("broken.yaml"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("a"), withIntermediateDirectories: true)
        try "workflow: w\nevery: 1h\n".write(
            to: directory.appendingPathComponent("a/ok.yaml"), atomically: true, encoding: .utf8)
        let sut = ScheduleStore(directory: directory, enabledFile: try temporary.file("schedule-enabled.json"))

        // When
        let snapshot = await sut.reload()

        // Then
        #expect(snapshot.failures.map(\.path) == ["broken.yaml"], "the decode failure must surface, and only it")
        #expect(snapshot.entries.map(\.schedule.id) == ["a/ok"], "the other file loads")
    }

    // MARK: - Private
    // The error a call throws, or nil when it returns.
    private func failure<Value>(of body: () async throws -> Value) async -> (any Error)? {
        do {
            _ = try await body()

            return nil
        } catch {
            return error
        }
    }
}
