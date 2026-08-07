//
//  SpecCatalog.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

// The workflow catalog in spec format — the same scan/cache/failure-ledger
// discipline as the other stores, loading `Spec.Program` through the one forge
// loader. Identity is the file basename; a `name:` in the body is metadata and
// must agree when present.
actor SpecCatalog {
    struct Catalog: Sendable {
        // MARK: - Property
        let entries: [(name: String, program: Spec.Program, source: String)]
        let failures: [LoadFailure]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    enum Lookup {
        case found(Spec.Program)
        case invalid(reason: String)
        case unobserved(reason: String)
        case missing
    }

    private struct Entry {
        // MARK: - Property
        let name: String
        let program: Spec.Program
        let mtime: Date
        let source: String

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let directory: URL?
    let loader: SpecLoader

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
                .map { entry in (entry.name, entry.program, entry.source) }
                .sorted { left, right in left.name < right.name },
            failures: (Array(failureCache.values) + collisions + scanFailures)
                .sorted { left, right in left.path < right.path }
        )
    }

    // MARK: - Initializer
    init(directory: URL?, loader: SpecLoader) {
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
                let program = try loader.load(data)

                if let declared = program.name, declared != base {
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

                candidates.append(
                    (
                        base,
                        file.source,
                        Entry(name: base, program: program, mtime: mtime, source: file.source)
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

        if let entry = cache[name] { return .found(entry.program) }

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

// `use` and the dispatcher resolve named specs through the same catalog the
// daemon serves — one door, one cache, one failure ledger.
extension SpecCatalog: SpecStore {
    func spec(named name: String) async throws -> Spec.Program {
        switch await resolve(name) {
        case .found(let program):
            return program

        case .invalid(let reason):
            throw ExecutionError("workflow '\(name)' is broken — \(reason)")

        case .unobserved(let reason):
            throw ExecutionError("workflow '\(name)' could not be resolved — \(reason)")

        case .missing:
            throw ExecutionError("workflow not found: \(name)")
        }
    }
}
