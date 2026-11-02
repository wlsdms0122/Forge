//
//  SchedulerFixture.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
@testable import Forge

// The stage that scheduler tests set up.
//
// Running a scheduler at all requires a workflow reader, schedule definitions, a fire
// ledger, and a runner, so a test spends twenty lines before reaching its actual concern
// (does the policy run correctly). Those twenty lines are the same in every test, so they
// are set up once here. The stage's lifetime is owned by the temporary directory.
struct SchedulerFixture {
    // A workflow fixture: its path is its identity, so it carries path and body together.
    struct WorkflowFixture {
        // MARK: - Property
        let path: String
        let yaml: String

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let temporary: TemporaryDirectory

    // MARK: - Initializer
    init(_ name: String) {
        temporary = TemporaryDirectory(name)
    }

    // MARK: - Public
    // A workflow that leaves its tag in a marker file when run. Who ran, and when, is read from the file contents.
    func markerWorkflow(
        path: String,
        marker: URL,
        tag: String,
        sleep: Double,
        endTag: String? = nil
    ) -> WorkflowFixture {
        var script = "printf '\(tag)' >> '\(marker.path)'; sleep \(sleep)"

        if let endTag {
            script += "; printf '\(endTag)' >> '\(marker.path)'"
        }

        return WorkflowFixture(
            path: path,
            yaml: """
            failing: [nonzero_exit, timeout]
            body:
              - let: s
                value: { call: { procedure: shell, arguments: { command: ["/bin/sh", "-c", "\(script)"] } } }
            """
        )
    }

    func write(_ workflow: WorkflowFixture, to directory: URL) throws {
        try workflowFile(workflow.yaml).write(
            to: directory.appendingPathComponent(workflow.path),
            atomically: true, encoding: .utf8)
    }

    func marker(_ name: String) throws -> URL {
        try temporary.make("marker-\(name)").appendingPathComponent("m")
    }

    func read(_ marker: URL) -> String {
        (try? String(contentsOf: marker, encoding: .utf8)) ?? ""
    }

    func reader(directory: URL?) throws -> WorkflowReader {
        try WorkflowReader(directory: directory)
    }

    func runner(
        workflows: WorkflowReader,
        policy: [String: [String]] = ["*": ["*"]]
    ) -> WorkflowRunner {
        WorkflowRunner(
            workflows: workflows,
            eventBus: WorkflowEventBus(),
            policyStore: PolicyStore(seed: policy),
            pool: WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max),
            workRegistry: WorkRegistry(),
            tokenAuthority: TokenAuthority(),
            capabilities: CapabilitySet(
                shell: LiveShell(),
                agent: LiveAgent(executor: AgentExecutor(backend: StubBackend("noop"))),
                resources: LiveResources(workingDirectory: WorkingDirectory(directory: nil))
            )
        )
    }

    func scheduler(
        workflows: [WorkflowFixture],
        scheduleYAML: [String: String],
        ledgerPath: URL? = nil
    ) async throws -> WorkflowScheduler {
        let workflowDirectory = try temporary.make("wf")

        for workflow in workflows {
            try write(workflow, to: workflowDirectory)
        }

        let scheduleDirectory = try temporary.make("schedule")

        for (id, yaml) in scheduleYAML {
            try yaml.write(
                to: scheduleDirectory.appendingPathComponent("\(id).yaml"),
                atomically: true, encoding: .utf8)
        }

        let seeds = scheduleYAML.mapValues(Self.declaredWorkflow)
        let store = try scheduleStore(directory: scheduleDirectory, ids: seeds)
        let path = try ledgerPath ?? temporary.file("fire-ledger.json")
        let reader = try self.reader(directory: workflowDirectory)

        return WorkflowScheduler(
            workflows: reader,
            store: store,
            ledger: FireLedger(path: path),
            runner: runner(workflows: reader),
            tickIntervalSeconds: 1
        )
    }

    // A once stage whose one-shot is the file `onceFileName` written into `directory`.
    func onceScheduler(
        onceYAML: String,
        onceFileName: String,
        directory: URL,
        marker: URL
    ) async throws -> (scheduler: WorkflowScheduler, ledger: FireLedger, onceFile: URL) {
        let onceFile = directory.appendingPathComponent(onceFileName)
        try onceYAML.write(to: onceFile, atomically: true, encoding: .utf8)
        let stage = try await onceStage(
            directory: directory,
            marker: marker,
            ids: [(onceFileName as NSString).deletingPathExtension: Self.declaredWorkflow(onceYAML)])

        return (stage.scheduler, stage.ledger, onceFile)
    }

    // A scheduler over `directory` whose workflow root holds `wfonce.yaml`, a workflow that leaves "1" in `marker`.
    func onceStage(
        directory: URL,
        marker: URL,
        ids: [String: String] = [:]
    ) async throws -> (scheduler: WorkflowScheduler, ledger: FireLedger, store: ScheduleStore) {
        let workflow = markerWorkflow(path: "wfonce.yaml", marker: marker, tag: "1", sleep: 0.1)
        let workflowDirectory = try temporary.make("once-wf")
        try write(workflow, to: workflowDirectory)
        let store = try scheduleStore(directory: directory, ids: ids)
        let ledger = FireLedger(path: try temporary.make("once-led").appendingPathComponent("l.json"))
        let reader = try self.reader(directory: workflowDirectory)
        let scheduler = WorkflowScheduler(
            workflows: reader,
            store: store,
            ledger: ledger,
            runner: runner(workflows: reader),
            tickIntervalSeconds: 1
        )

        return (scheduler, ledger, store)
    }

    // A store that starts enabled, with (id, workflow) pre-seeded into the ledger.
    func scheduleStore(directory: URL, ids: [String: String]) throws -> ScheduleStore {
        let enabledFile = try temporary.make("enabled").appendingPathComponent("schedule-enabled.json")
        try JSONSerialization.data(withJSONObject: ids).write(to: enabledFile)

        return ScheduleStore(directory: directory, enabledFile: enabledFile)
    }

    // A path that cannot be created because its parent is a file — triggers a ledger persist failure.
    func unwritableLedgerPath(_ tag: String) throws -> URL {
        let blocker = try temporary.make("led-block-\(tag)").appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)

        return blocker.appendingPathComponent("sub").appendingPathComponent("l.json")
    }

    // MARK: - Private
    private static func declaredWorkflow(_ yaml: String) -> String {
        yaml.split(separator: "\n")
            .first { line in line.hasPrefix("workflow:") }?
            .split(separator: ":", maxSplits: 1).last
            .map { value in value.trimmingCharacters(in: .whitespaces) } ?? ""
    }
}
