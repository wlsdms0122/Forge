//
//  SpecCatalog.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp
import WarpSyntax
import WarpYAML

// The workflow catalog — the same scan/cache/failure-ledger discipline as the
// other stores, each file read by the YAML front end and loaded as a document.
// Identity is the file basename, and the file declares one procedure under it.
actor SpecCatalog {
    struct Catalog: Sendable {
        // MARK: - Property
        let entries: [(name: String, module: Warp.Module, source: String)]
        let failures: [LoadFailure]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    enum Lookup {
        case found(Warp.Module)
        case invalid(reason: String)
        case unobserved(reason: String)
        case missing
    }

    private struct Entry {
        // MARK: - Property
        let name: String
        let module: Warp.Module
        let mtime: Date
        let source: String

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let directory: URL?
    let frontend: YAMLFrontend

    private var cache: [String: Entry] = [:]
    private var failureCache: [String: LoadFailure] = [:]
    private var collisions: [LoadFailure] = []
    private var collidedNames: [String: [String]] = [:]
    private var scanObstructions: [StoreScan.Obstruction] = []

    private var currentCatalog: Catalog {
        let scanFailures = scanObstructions.map { obstruction in
            LoadFailure(
                path: "<scan>",
                reason: "workflow directory scan incomplete — \(obstruction.description)",
                mtime: .distantPast
            )
        }

        return Catalog(
            entries: cache.values
                .map { entry in (entry.name, entry.module, entry.source) }
                .sorted { left, right in left.name < right.name },
            failures: (Array(failureCache.values) + collisions + scanFailures)
                .sorted { left, right in left.path < right.path }
        )
    }

    // MARK: - Initializer
    init(directory: URL?, frontend: YAMLFrontend) {
        self.directory = directory
        self.frontend = frontend
    }

    // MARK: - Public
    @discardableResult
    func catalog() async -> Catalog {
        guard let directory else {
            cache.removeAll()
            failureCache.removeAll()
            collisions.removeAll()
            collidedNames.removeAll()
            scanObstructions.removeAll()

            return currentCatalog
        }

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory.path) else {
            scanObstructions = [
                .init(
                    scope: "",
                    reason: "configured workflow directory is not visible (\(directory.path))"
                )
            ]

            return currentCatalog
        }

        var entriesBySource: [String: Entry] = [:]

        for entry in cache.values { entriesBySource[entry.source] = entry }

        var ledger = LoadFailureLedger(prior: failureCache)
        var candidates: [(key: String, source: String, value: Entry)] = []
        var scan = scanStoreFiles(in: directory, pathExtension: specFileExtension)
        var observedSources: Set<String> = []

        for file in scan.files {
            let url = file.url

            guard
                let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                let mtime = attributes[.modificationDate] as? Date
            else {
                scan.obstructions.append(
                    .init(
                        scope: file.source,
                        reason: "file metadata could not be read"
                            + " — existence observed, content unknown"
                    )
                )

                continue
            }

            observedSources.insert(file.source)

            if let existing = entriesBySource[file.source], existing.mtime == mtime {
                candidates.append((existing.name, file.source, existing))

                continue
            }

            if ledger.reuse(source: file.source, mtime: mtime) { continue }

            let base = url.deletingPathExtension().lastPathComponent

            do {
                let module = try load(Data(contentsOf: url))

                // Forge's convention on top of the language: a workflow file
                // declares one procedure and names it after the file. The
                // language lets a module declare many — this is where a workflow
                // says it is one thing you can run by the name you know it by.
                guard module.procedures.keys.map(\.spelling) == [base] else {
                    ledger.record(
                        source: file.source,
                        reason: "a workflow file declares exactly one procedure named"
                            + " after the file — expected 'procedures: { \(base): ... }',"
                            + " found \(module.procedures.keys.map(\.spelling).sorted().map { key in "'\(key)'" })",
                        mtime: mtime,
                        stderrLine: "workflow procedure/filename mismatch (\(file.source))",
                        name: base
                    )

                    continue
                }

                candidates.append(
                    (
                        base,
                        file.source,
                        Entry(name: base, module: module, mtime: mtime, source: file.source)
                    )
                )
            } catch {
                ledger.record(
                    source: file.source,
                    reason: "\(error)",
                    mtime: mtime,
                    stderrLine: "workflow load failed (\(file.source)): \(error)",
                    name: base
                )
            }
        }

        func isUnobserved(_ source: String) -> Bool {
            !observedSources.contains(source) && scan.isUnobserved(source: source)
        }

        for entry in cache.values where isUnobserved(entry.source) {
            candidates.append((entry.name, entry.source, entry))
        }

        for (source, failure) in failureCache where isUnobserved(source) {
            _ = ledger.reuse(source: source, mtime: failure.mtime)
        }

        var (live, collided) = partitionUniqueKeys(candidates)

        for (key, sources) in collidedNames where sources.contains(where: isUnobserved) {
            live.removeValue(forKey: key)

            if !collided.contains(where: { entry in entry.key == key }) {
                collided.append((key: key, sources: sources))
            }
        }

        let freshCollisions = collisionFailures(kind: "workflow name", collided)
        ledger.recordLegacyJSONSpecs(in: directory, kind: "workflow")

        cache = live
        failureCache = ledger.fresh
        collisions = freshCollisions
        scanObstructions = scan.obstructions
        collidedNames = Dictionary(
            uniqueKeysWithValues: collided.map { entry in (entry.key, entry.sources) }
        )

        return currentCatalog
    }

    func all() async -> Catalog {
        await catalog()
    }

    // A workflow file as the front end writes it, loaded the way any runtime
    // receives a document.
    func load(_ data: Data) throws -> Warp.Module {
        let document = try frontend.document(from: data)

        return try Loader().load(document, identity: try Identity.of(document))
    }

    // An inline spec: one procedure written in the YAML notation, run under the
    // sigil the dispatch door fixes, which a run starts from.
    nonisolated func inline(_ spec: Warp.Value) throws -> Warp.Module {
        let procedure = try Loader(registry: try .yaml()).procedure(from: spec, in: .yaml)

        return try Warp.Module(
            procedures: [try Name(WorkflowDispatchMethod.inlineSigil): procedure.with(access: .public)]
        )
    }

    func resolve(_ name: String) async -> Lookup {
        await catalog()

        if let entry = cache[name] { return .found(entry.module) }

        if let failure = failureCache.values.first(where: { failure in failure.name == name }) {
            return .invalid(reason: failure.reason)
        }

        if let sources = collidedNames[name] {
            return .invalid(
                reason: "duplicate workflow name '\(name)' — all definitions excluded"
                    + " (\(sources.joined(separator: ", ")))"
            )
        }

        if !scanObstructions.isEmpty {
            return .unobserved(
                reason: "workflow directory was not fully enumerated this reload — '\(name)'"
                    + " may exist in an unobserved path"
                    + " (\(scanObstructions.map(\.description).joined(separator: "; ")))"
            )
        }

        return .missing
    }

    // MARK: - Private
}

// The set a link is handed. `gcc main.cpp a.cpp b.cpp` is given its whole world
// at once and so is this — every workflow the daemon can see goes into every
// link, and which one runs is the entry name.
//
// This is the one place the "everything, every time" model costs something: the
// corpus is parsed and validated on reload rather than on demand. It is a
// directory of workflow files, so that is cheap; if it stops being cheap the
// answer is caching the parse, not resolving names lazily, because lazily is
// how a duplicate symbol goes unnoticed until someone happens to call it.
extension SpecCatalog {
    func module(named name: String) async throws -> Warp.Module {
        switch await resolve(name) {
        case let .found(module):
            return module

        case let .invalid(reason):
            throw ExecutionError("workflow '\(name)' is broken — \(reason)")

        case let .unobserved(reason):
            throw ExecutionError("workflow '\(name)' could not be resolved — \(reason)")

        case .missing:
            throw ExecutionError("workflow not found: \(name)")
        }
    }

    // The workflows the daemon can see, without the vocabulary a link adds.
    func modules() async -> [Warp.Module] {
        await catalog().entries.map(\.module)
    }
}

