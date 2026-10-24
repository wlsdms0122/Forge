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

// The workflow catalog, with the same scan and failure-ledger discipline as
// the other stores. At a reload every file is read by the YAML front end
// leaning on the library and on the other files, loaded as a document and
// built against what builds; a file that does not is a failure, and the
// entries are the files that built. Identity is the file basename, and the
// file declares one procedure under it.
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

    // A file the scan saw, with when it last changed.
    private struct Observed {
        // MARK: - Property
        let file: ScannedFile
        let mtime: Date

        var stamp: String { "\(file.source)\t\(mtime.timeIntervalSinceReferenceDate)" }

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let directory: URL?

    private var cache: [String: Entry] = [:]
    private var failureCache: [String: LoadFailure] = [:]
    private var legacyFailures: [String: LoadFailure] = [:]
    private var collisions: [LoadFailure] = []
    private var collidedNames: [String: [String]] = [:]
    private var scanObstructions: [StoreScan.Obstruction] = []

    // The observation the entries and failures were read from: each file
    // with its modification time, and what the scan could not see.
    private var generation: [String]?

    // The reload in progress, which a caller arriving during it waits for.
    private var reloading: Task<Void, Never>?

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
            failures: (Array(failureCache.values) + Array(legacyFailures.values) + collisions + scanFailures)
                .sorted { left, right in left.path < right.path }
        )
    }

    // MARK: - Initializer
    init(directory: URL?) {
        self.directory = directory
    }

    // MARK: - Public
    @discardableResult
    func catalog() async -> Catalog {
        guard let directory else {
            cache.removeAll()
            failureCache.removeAll()
            legacyFailures.removeAll()
            collisions.removeAll()
            collidedNames.removeAll()
            scanObstructions.removeAll()
            generation = nil

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

        var scan = scanStoreFiles(in: directory, pathExtension: specFileExtension)
        var observed: [Observed] = []

        for file in scan.files {
            guard
                let attributes = try? fileManager.attributesOfItem(atPath: file.url.path),
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

            observed.append(Observed(file: file, mtime: mtime))
        }

        var legacy = LoadFailureLedger(prior: legacyFailures)

        legacy.recordLegacyJSONSpecs(in: directory, kind: "workflow")
        legacyFailures = legacy.fresh

        // The files lean on each other, so a change to one is a reload of
        // all of them.
        let observation = observed.map(\.stamp) + scan.obstructions.map(\.description)

        guard observation != generation else { return currentCatalog }

        // One reload at a time: a caller arriving while one runs waits for
        // it and looks again.
        if let reloading {
            await reloading.value

            return await catalog()
        }

        let reload = Task { await self.reload(observed, scan: scan, observation: observation) }

        reloading = reload
        await reload.value
        reloading = nil

        return currentCatalog
    }

    func all() async -> Catalog {
        await catalog()
    }

    // An inline spec: one procedure written in the YAML notation, run under the
    // sigil the dispatch door fixes, which a run starts from.
    nonisolated func inline(_ spec: Warp.Value) throws -> Warp.Module {
        let procedure = try Loader(registry: .yaml).procedure(from: spec, in: .yaml)

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
    // Every observed file read, loaded and built again, and the entries and
    // failures of this observation put in place.
    private func reload(_ observed: [Observed], scan: StoreScan, observation: [String]) async {
        var ledger = LoadFailureLedger(prior: failureCache)
        var candidates = spent(observed, recording: &ledger)
        let observedSources = Set(observed.map(\.file.source))

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
        let standing = await built(live, recording: &ledger)

        cache = standing
        failureCache = ledger.fresh
        collisions = freshCollisions
        scanObstructions = scan.obstructions
        collidedNames = Dictionary(
            uniqueKeysWithValues: collided.map { entry in (entry.key, entry.sources) }
        )
        generation = observation
    }

    // The observed files read leaning on each other and on the library,
    // each loaded the way a runtime receives a document and held to Forge's
    // convention of one procedure named after the file. What does not read,
    // load or keep the convention is recorded.
    private func spent(
        _ observed: [Observed],
        recording ledger: inout LoadFailureLedger
    ) -> [(key: String, source: String, value: Entry)] {
        var texts: [(observed: Observed, text: String)] = []

        for file in observed {
            do {
                texts.append((file, try String(contentsOf: file.file.url, encoding: .utf8)))
            } catch {
                record(file, refusal: "\(error)", in: &ledger)
            }
        }

        let frontend: YAMLFrontend

        do {
            let leaning = try ForgeSpec.frontend(leaningOn: texts.map(\.text))

            for (index, refusal) in leaning.refusals {
                record(texts[index].observed, refusal: "\(refusal)", in: &ledger)
            }

            texts = texts.indices.filter { index in leaning.refusals[index] == nil }.map { index in texts[index] }
            frontend = leaning.frontend
        } catch {
            for (file, _) in texts {
                record(file, refusal: "\(error)", in: &ledger)
            }

            return []
        }

        var candidates: [(key: String, source: String, value: Entry)] = []

        for (file, text) in texts {
            let base = file.file.url.deletingPathExtension().lastPathComponent

            do {
                let document = try frontend.document(from: text)
                let module = try Loader().load(document, identity: try Identity.of(document))

                // Forge's convention on top of the language: a workflow file
                // declares one procedure and names it after the file. The
                // language lets a module declare many — this is where a workflow
                // says it is one thing you can run by the name you know it by.
                guard module.procedures.keys.map(\.spelling) == [base] else {
                    ledger.record(
                        source: file.file.source,
                        reason: "a workflow file declares exactly one procedure named"
                            + " after the file — expected 'procedures: { \(base): ... }',"
                            + " found \(module.procedures.keys.map(\.spelling).sorted().map { key in "'\(key)'" })",
                        mtime: file.mtime,
                        stderrLine: "workflow procedure/filename mismatch (\(file.file.source))",
                        name: base
                    )

                    continue
                }

                candidates.append(
                    (
                        base,
                        file.file.source,
                        Entry(name: base, module: module, mtime: file.mtime, source: file.file.source)
                    )
                )
            } catch {
                record(file, refusal: "\(error)", in: &ledger)
            }
        }

        return candidates
    }

    // The entries that build: each against the library, the natives, the
    // standard vocabulary and the entries that built before it, until a
    // round admits none. An entry left is recorded with its build refusal,
    // and no run links it.
    private func built(
        _ live: [String: Entry],
        recording ledger: inout LoadFailureLedger
    ) async -> [String: Entry] {
        var standing: [String: Entry] = [:]
        var pending = live.values.sorted { left, right in left.name < right.name }
        var refusals: [String: String] = [:]

        do {
            let linkables = try ForgeSpec.linkables()
            var admitted = true

            while admitted, !pending.isEmpty {
                admitted = false

                for entry in pending {
                    do {
                        _ = try await Builder().build([entry.module] + standing.values.map(\.module) + linkables)
                        standing[entry.name] = entry
                        admitted = true
                    } catch {
                        refusals[entry.name] = "\(error)"
                    }
                }

                pending.removeAll { entry in standing[entry.name] != nil }
            }
        } catch {
            for entry in pending {
                refusals[entry.name] = "\(error)"
            }
        }

        for entry in pending {
            ledger.record(
                source: entry.source,
                reason: "build: \(refusals[entry.name] ?? "refused")",
                mtime: entry.mtime,
                stderrLine: "workflow build failed (\(entry.source)): \(refusals[entry.name] ?? "refused")",
                name: entry.name
            )
        }

        return standing
    }

    private func record(_ file: Observed, refusal: String, in ledger: inout LoadFailureLedger) {
        ledger.record(
            source: file.file.source,
            reason: refusal,
            mtime: file.mtime,
            stderrLine: "workflow load failed (\(file.file.source)): \(refusal)",
            name: file.file.url.deletingPathExtension().lastPathComponent
        )
    }
}

// The set a link is handed: every workflow that built goes into every link,
// and which one runs is the entry name. The corpus is read and built at a
// reload rather than on demand, so a duplicate symbol is refused there and
// not when someone happens to call it.
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

    // The workflows that built, without the vocabulary a link adds.
    func modules() async -> [Warp.Module] {
        await catalog().entries.map(\.module)
    }
}

