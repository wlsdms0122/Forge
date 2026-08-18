//
//  SpecCatalog.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp
import WarpIR
import WarpYAML

// The workflow catalog in spec format — the same scan/cache/failure-ledger
// discipline as the other stores, loading `Warp.Module` through the one forge
// loader. Identity is the file basename; a `name:` in the body is metadata and
// must agree when present.
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
    let loader: Loader

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
    init(directory: URL?, loader: Loader) {
        self.directory = directory
        self.loader = loader
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
                let data = try Data(contentsOf: url)
                // The names the daemon supplies are declared here rather than by
                // every workflow author, which is what the language's removed
                // context tier used to do for us.
                let module = try loader
                    .load(ForgeSpec.seeding(document: try YAMLParser().parse(data)))

                if let declared = module.name, declared != base {
                    ledger.record(
                        source: file.source,
                        reason: "workflow name '\(declared)' must equal the file basename"
                            + " '\(base)' — identity is the filename (rename the file or drop"
                            + " the name from the body)",
                        mtime: mtime,
                        stderrLine: "workflow name/filename mismatch (\(file.source)):"
                            + " name '\(declared)' vs basename '\(base)'",
                        name: base
                    )

                    continue
                }

                // Forge's convention on top of the language: a workflow file
                // declares one procedure and names it after the file. The
                // language lets a module declare many — this is where a workflow
                // says it is one thing you can run by the name you know it by.
                guard Array(module.procedures.keys) == [base] else {
                    ledger.record(
                        source: file.source,
                        reason: "a workflow file declares exactly one procedure named"
                            + " after the file — expected 'procedures: { \(base): ... }',"
                            + " found \(module.procedures.keys.sorted().map { key in "'\(key)'" })",
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
        case .found(let module):
            return module

        case .invalid(let reason):
            throw ExecutionError("workflow '\(name)' is broken — \(reason)")

        case .unobserved(let reason):
            throw ExecutionError("workflow '\(name)' could not be resolved — \(reason)")

        case .missing:
            throw ExecutionError("workflow not found: \(name)")
        }
    }

    // The workflows the daemon can see. What a link additionally needs —
    // forge's verbs and the standard vocabulary — is `ForgeSpec.linkables`, and
    // it is kept out of here on purpose: a caller filtering this list is
    // filtering workflows, and dropping the vocabulary alongside one would take
    // every verb with it.
    func modules() async -> [Warp.Module] {
        await catalog().entries.map(\.module)
    }
}

// The `dlopen` door, and only that: a name reaching here came from IR forge
// lowered while running, which linking never promised to have resolved.
extension SpecCatalog: ProcedureCatalog {
    func procedure(named name: String) async throws -> Warp.Procedure {
        for module in await modules() {
            if let procedure = module.procedures[name] { return procedure }
        }

        throw ExecutionError("procedure not found: \(name)")
    }
}
