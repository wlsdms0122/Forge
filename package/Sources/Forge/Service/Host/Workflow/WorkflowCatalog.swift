//
//  WorkflowCatalog.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp
import WarpSyntax
import WarpYAML

// The workflows under the root, with the same scan and failure-ledger
// discipline as the other stores. A workflow is a `.yaml` file, addressed by
// its path relative to the root, and is a program of its own: read by the
// YAML front end leaning on the library alone, loaded as a document and built
// against the vocabulary into the image its runs run. A file that does not is
// a failure. A file is read again only where it changed.
actor WorkflowCatalog {
    struct Snapshot: Sendable {
        // MARK: - Property
        let entries: [Workflow]
        let failures: [LoadFailure]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    enum Lookup {
        case found(Workflow)
        case invalid(reason: String)
        case unobserved(reason: String)
        case missing
    }

    private struct Entry {
        // MARK: - Property
        let workflow: Workflow
        let mtime: Date
        let image: Image

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    // What stands in an inline spec's path.
    static let inlineSigil = "<inline>"

    let directory: URL?

    // What the workflows are written over, which every run of one links.
    let vocabulary: ForgeVocabulary

    private let builder: WorkflowBuilder
    private var cache: [String: Entry] = [:]
    private var failureCache: [String: LoadFailure] = [:]
    private var scanObstructions: [StoreScan.Obstruction] = []

    // The observation the entries and failures were read from: each file
    // with its modification time, and what the scan could not see.
    private var generation: [String]?

    // The reload in progress, which a caller arriving during it waits for.
    private var reloading: Task<String, Never>?

    private var currentSnapshot: Snapshot {
        let scanFailures = scanObstructions.map { obstruction in obstruction.failure(kind: "root") }

        return Snapshot(
            entries: cache.values
                .map(\.workflow)
                .sorted { left, right in left.path < right.path },
            failures: (Array(failureCache.values) + scanFailures)
                .sorted { left, right in left.path < right.path }
        )
    }

    // MARK: - Initializer
    init(directory: URL?, builder: WorkflowBuilder) {
        self.directory = directory
        self.vocabulary = builder.vocabulary
        self.builder = builder
    }

    // MARK: - Public
    // The root, reloaded where it changed and answered as a snapshot: a
    // reload announces on stderr each failure new to it.
    @discardableResult
    func reload() async -> Snapshot {
        guard let directory else {
            cache.removeAll()
            failureCache.removeAll()
            scanObstructions.removeAll()
            generation = nil

            return currentSnapshot
        }

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory.path) else {
            scanObstructions = [
                .init(
                    scope: "",
                    reason: "configured root is not visible (\(directory.path))"
                )
            ]

            return currentSnapshot
        }

        let observed = await observing(StoreScan(directory: directory, pathExtension: StoreScan.specFileExtension))

        FileHandle.standardError.write(Data(observed.announcement.utf8))

        return observed.snapshot
    }

    // The files at these paths read the way a reload reads the root's, for
    // a gate that admits what the daemon admits and reports what it records.
    func reload(of paths: [String]) async -> Snapshot {
        await observing(
            StoreScan(files: paths.map { path in ScannedFile(url: URL(fileURLWithPath: path), source: path) })
        )
        .snapshot
    }

    // An inline spec: one procedure written in the YAML notation, read the
    // way a file is, leaning on the library, and declared as the entry a run
    // starts from.
    func inline(_ spec: [String: JSONValue]) async throws -> Workflow {
        var procedure = spec

        procedure["access"] = .string("public")

        let written = JSONValue.object(["procedures": .object([Workflow.entry: .object(procedure)])])
        let spent: Data

        // The caller wrote an object and no text, so a refusal names its
        // place in the document and not a line of the text written here.
        do {
            spent = try vocabulary.frontend.document(from: try JSONEncoder().encode(written)).document
        } catch let refusal as AuthoringError {
            throw WorkflowValidationError(refusal.message)
        }

        let document = try BinaryEncoding().value(from: spent)

        return try Workflow(
            path: Self.inlineSigil,
            module: try Loader().load(document),
            documentation: nil
        )
    }

    // The image a run of this workflow runs: for a file under the root, the
    // one its reload built; for an inline spec, its module built alone.
    func image(of workflow: Workflow) async throws -> Image {
        if let entry = cache[workflow.path], entry.workflow.module.identity == workflow.module.identity {
            return entry.image
        }

        return try await builder.image(of: workflow.module)
    }

    func resolve(_ path: String) async -> Lookup {
        await reload()

        if let entry = cache[path] { return .found(entry.workflow) }

        if let failure = failureCache[path] { return .invalid(reason: failure.reason) }

        if !scanObstructions.isEmpty {
            return .unobserved(
                reason: "root was not fully enumerated this reload, so '\(path)'"
                    + " may exist in an unobserved path"
                    + " (\(scanObstructions.map(\.description).joined(separator: "; ")))"
            )
        }

        return .missing
    }

    // MARK: - Private
    // The snapshot of the files a scan saw, reloaded where any of them
    // changed since the observation the entries were read from, and what
    // the reload announces, nothing where this call ran none.
    private func observing(_ scan: StoreScan) async -> (snapshot: Snapshot, announcement: String) {
        var scan = scan
        let observed = scan.observe()
        let generation = observed.map { file in "\(file.file.source)\t\(file.mtime.timeIntervalSinceReferenceDate)" }
            + scan.obstructions.map(\.description)

        guard generation != self.generation else { return (currentSnapshot, "") }

        // One reload at a time: a caller arriving while one runs waits for
        // it and looks again.
        if let reloading {
            _ = await reloading.value

            return await observing(scan)
        }

        let reload = Task { await self.reload(observed, scan: scan, observation: generation) }

        reloading = reload

        let announcement = await reload.value

        reloading = nil

        return (currentSnapshot, announcement)
    }

    // The entries and failures of this observation put in place: a file
    // unchanged since the last keeps what it was, one the scan could not
    // see keeps its standing, and any other is read and built again. What is
    // announced for the failures new to it.
    private func reload(_ observed: [ObservedFile], scan: StoreScan, observation: [String]) async -> String {
        var ledger = LoadFailureLedger(prior: failureCache)
        var entries: [String: Entry] = [:]
        let observedSources = Set(observed.map(\.file.source))

        for file in observed {
            let source = file.file.source

            if let entry = cache[source], entry.mtime == file.mtime {
                entries[source] = entry

                continue
            }

            if ledger.reuse(source: source, mtime: file.mtime) { continue }

            if let entry = await built(file, recording: &ledger) {
                entries[source] = entry
            }
        }

        for (source, entry) in cache where !observedSources.contains(source) && scan.isUnobserved(source: source) {
            entries[source] = entry
        }

        for (source, failure) in failureCache
        where !observedSources.contains(source) && scan.isUnobserved(source: source) {
            _ = ledger.reuse(source: source, mtime: failure.mtime)
        }

        cache = entries
        failureCache = ledger.fresh
        scanObstructions = scan.obstructions
        generation = observation

        return ledger.announcement
    }

    // A file read leaning on the library, loaded the way a runtime receives
    // a document, held to Forge's convention and built, or recorded with what
    // refused it.
    private func built(_ file: ObservedFile, recording ledger: inout LoadFailureLedger) async -> Entry? {
        let source = file.file.source
        var origin: DocumentOrigin?

        do {
            let text = try String(contentsOf: file.file.url, encoding: .utf8)
            let spent = try vocabulary.frontend.document(from: text)
            let document = try BinaryEncoding().value(from: spent.document)
            let loading = DocumentOrigin(identity: try Identity.of(document), origin: spent.origin)

            origin = loading

            let module = try Loader().load(document)

            if let breach = convention(module) {
                ledger.record(
                    source: source,
                    reason: breach,
                    mtime: file.mtime,
                    stderrLine: "workflow has no entry (\(source)): \(breach)"
                )

                return nil
            }

            let workflow = try Workflow(
                path: source,
                module: module,
                documentation: try vocabulary.frontend.documentation(from: text)
            )

            do {
                return Entry(workflow: workflow, mtime: file.mtime, image: try await builder.image(of: module))
            } catch {
                let refusal = loading.described(error)

                ledger.record(
                    source: source,
                    reason: "build: \(refusal)",
                    mtime: file.mtime,
                    stderrLine: "workflow build failed (\(source)): \(refusal)"
                )

                return nil
            }
        } catch {
            let refusal = origin.map { origin in origin.described(error) } ?? "\(error)"

            ledger.record(
                source: source,
                reason: refusal,
                mtime: file.mtime,
                stderrLine: "workflow load failed (\(source)): \(refusal)"
            )

            return nil
        }
    }

    // Forge's convention on top of the language: a workflow file declares
    // its entry, a public procedure named `main`, which a run starts from.
    // The breach, where the file makes one.
    private func convention(_ module: Warp.Module) -> String? {
        guard
            let entry = try? Warp.Name(Workflow.entry),
            let procedure = module.procedures[entry]
        else {
            return "a workflow file declares the procedure '\(Workflow.entry)' a run starts from;"
                + " found \(module.procedures.keys.map { key in "'\(key.spelling)'" }.sorted().joined(separator: ", "))"
        }

        guard procedure.access == .public else {
            return "'\(Workflow.entry)' is the procedure a run starts from, so it is 'access: public'"
        }

        return nil
    }
}

extension WorkflowCatalog {
    func workflow(at path: String) async throws -> Workflow {
        switch await resolve(path) {
        case let .found(workflow):
            return workflow

        case let .invalid(reason):
            throw WorkflowValidationError("workflow '\(path)' is broken: \(reason)")

        case let .unobserved(reason):
            throw CatalogIncomplete("workflow '\(path)' could not be resolved: \(reason)")

        case .missing:
            throw WorkflowNotFound("workflow not found: \(path)")
        }
    }
}
