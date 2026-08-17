//
//  SchedulerFixture.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
@testable import Forge

/// The stage that scheduler tests set up.
///
/// Running a scheduler at all requires a workflow catalog, schedule definitions, a fire
/// ledger, and a runner, so a test spends twenty lines before reaching its actual concern
/// (does the policy run correctly). Those twenty lines are the same in every test, so they
/// are set up once here. The stage's lifetime is owned by the temporary directory.
struct SchedulerFixture {
    /// A spec-format workflow fixture — the file basename is its identity, so it carries name and body together.
    struct WorkflowFixture {
        // MARK: - Property
        let name: String
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
    /// A workflow that leaves its tag in a marker file when run. Who ran, and when, is read from the file contents.
    func markerWorkflow(
        name: String,
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
            name: name,
            yaml: """
            name: \(name)
            body:
              - id: s
                shell:
                  command: ["/bin/sh", "-c", "\(script)"]
            """
        )
    }

    func write(_ workflow: WorkflowFixture, to directory: URL) throws {
        try workflowFile(workflow.yaml, named: workflow.name).write(
            to: directory.appendingPathComponent("\(workflow.name).yaml"),
            atomically: true, encoding: .utf8)
    }

    func marker(_ name: String) throws -> URL {
        try temporary.make("marker-\(name)").appendingPathComponent("m")
    }

    func read(_ marker: URL) -> String {
        (try? String(contentsOf: marker, encoding: .utf8)) ?? ""
    }

    func catalog(directory: URL?) -> SpecCatalog {
        SpecCatalog(directory: directory, loader: ForgeSpec.loader())
    }

    func runner(catalog: SpecCatalog) -> SpecWorkflowRunner {
        SpecWorkflowRunner(
            catalog: catalog,
            eventBus: WorkflowEventBus(),
            policyStore: PolicyStore(seed: ["*": ["*"]]),
            pool: WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max),
            workRegistry: WorkRegistry(),
            tokenAuthority: TokenAuthority(),
            shell: LiveShell(),
            agent: LiveAgent(executor: Executor(backend: StubBackend("noop"))),
            resources: LiveResources(store: ResourceStore(directory: nil))
        )
    }

    func scheduler(
        workflows: [WorkflowFixture],
        scheduleYAML: [String: String],
        ledgerPath: URL? = nil
    ) throws -> WorkflowScheduler {
        let workflowDirectoryectory = try temporary.make("wf")

        for workflow in workflows {
            try write(workflow, to: workflowDirectoryectory)
        }

        let scheduleDirectoryectory = try temporary.make("schedule")

        for (id, yaml) in scheduleYAML {
            try yaml.write(
                to: scheduleDirectoryectory.appendingPathComponent("\(id).yaml"),
                atomically: true, encoding: .utf8)
        }

        let seeds = scheduleYAML.mapValues(Self.declaredWorkflow)
        let store = try scheduleStore(
            configDir: scheduleDirectoryectory,
            runtimeDirectory: try temporary.make("schedule-rt"),
            ids: seeds)
        let path = try ledgerPath ?? temporary.file("fire-ledger.json")
        let workflowStore = catalog(directory: workflowDirectoryectory)

        return WorkflowScheduler(
            workflowStore: workflowStore,
            store: store,
            ledger: FireLedger(path: path),
            runner: runner(catalog: workflowStore),
            tickIntervalSeconds: 1
        )
    }

    func onceScheduler(
        onceYAML: String,
        onceFileName: String,
        configDir: URL,
        runtimeDirectory: URL,
        marker: URL,
        runtimeOwned: Bool = false
    ) throws -> (scheduler: WorkflowScheduler, ledger: FireLedger, onceFile: URL) {
        let workflow = markerWorkflow(name: "wfonce", marker: marker, tag: "1", sleep: 0.1)
        let workflowDirectoryectory = try temporary.make("once-wf")
        try write(workflow, to: workflowDirectoryectory)
        let onceFile = (runtimeOwned ? runtimeDirectory : configDir)
            .appendingPathComponent(onceFileName)
        try onceYAML.write(to: onceFile, atomically: true, encoding: .utf8)
        let store = try scheduleStore(
            configDir: configDir,
            runtimeDirectory: runtimeDirectory,
            ids: [(onceFileName as NSString).deletingPathExtension: Self.declaredWorkflow(onceYAML)])
        let ledger = FireLedger(path: try temporary.make("once-led").appendingPathComponent("l.json"))
        let workflowStore = catalog(directory: workflowDirectoryectory)
        let scheduler = WorkflowScheduler(
            workflowStore: workflowStore,
            store: store,
            ledger: ledger,
            runner: runner(catalog: workflowStore),
            tickIntervalSeconds: 1
        )

        return (scheduler, ledger, onceFile)
    }

    /// A store that starts enabled, with (id, workflow) pre-seeded into the ledger.
    func scheduleStore(configDir: URL?, runtimeDirectory: URL?, ids: [String: String]) throws -> ScheduleStore {
        let state = try temporary.make("enabled").appendingPathComponent("schedule-enabled.json")
        try JSONSerialization.data(withJSONObject: ids).write(to: state)

        return ScheduleStore(configDir: configDir, runtimeDirectory: runtimeDirectory, stateFile: state)
    }

    /// A path that cannot be created because its parent is a file — triggers a ledger persist failure.
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
