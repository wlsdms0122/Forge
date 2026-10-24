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
        let entries: [(name: String, module: Warp.Module, source: String, documentation: Documentation)]
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

        // The prose the file writes beside its procedure.
        let documentation: Documentation

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

    // The front end the files of this observation were read with, leaning on
    // the library and on them.
    private var reading: YAMLFrontend?

    // The files that built, each compiled once a reload, in the order they
    // were compiled.
    private var compiled: [(name: String, compiled: Compiled)] = []

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
                .map { entry in (entry.name, entry.module, entry.source, entry.documentation) }
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
            reading = nil
            compiled.removeAll()

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

        var legacy = LoadFailureLedger(prior: legacyFailures)

        legacy.recordLegacyJSONSpecs(in: directory, kind: "workflow")
        legacyFailures = legacy.fresh

        return await observing(scanStoreFiles(in: directory, pathExtension: specFileExtension))
    }

    // The files at these paths read the way a reload reads the directory's,
    // for a gate that admits what the daemon admits.
    func catalog(of paths: [String]) async -> Catalog {
        await observing(
            StoreScan(files: paths.map { path in ScannedFile(url: URL(fileURLWithPath: path), source: path) })
        )
    }

    func all() async -> Catalog {
        await catalog()
    }

    // An inline spec: one procedure written in the YAML notation, read the
    // way a catalog file is, leaning on the library and on the catalog's
    // files, and declared public under the sigil the dispatch door fixes,
    // which a run starts from.
    func inline(_ spec: JSONValue) async throws -> Warp.Module {
        guard case var .object(procedure) = spec else {
            throw WorkflowValidationError("an inline spec is one procedure, written as an object")
        }

        procedure["access"] = .string("public")

        let text = try JSONEncoder().encode(
            JSONValue.object(["procedures": .object([WorkflowDispatchMethod.inlineSigil: .object(procedure)])])
        )

        await catalog()

        let document: Value

        // The caller wrote an object and no text, so a refusal names its
        // place in the document and not a line of the text written here.
        do {
            document = try (reading ?? ForgeSpec.frontend()).document(from: text)
        } catch let refusal as AuthoringError {
            throw refusal.refusal
        }

        return try Loader().load(document, identity: try Identity.of(document))
    }

    // The image a run of this module links: the module beside every other
    // file that built, as each was compiled at the reload, and the
    // vocabulary compiled once a process. A file of the catalog is linked as
    // it was compiled; another module, an inline spec, is compiled against
    // them, and a file declaring the name it runs by is left out, since the
    // caller's is the one meant.
    func image(running module: Warp.Module, entry: Name) async throws -> Image {
        await catalog()

        let standing = compiled
        let files = cache

        if let file = files[entry.spelling], file.module.identity == module.identity {
            return try await ForgeSpec.linked(standing.map(\.compiled))
        }

        let world = standing
            .filter { file in files[file.name]?.module.procedures[entry] == nil }
            .map(\.compiled)

        return try await ForgeSpec.linked(world + ForgeSpec.compiled([module], beside: world))
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
    // The catalog of the files a scan saw, reloaded where any of them
    // changed since the observation the entries were read from.
    private func observing(_ scan: StoreScan) async -> Catalog {
        let fileManager = FileManager.default
        var scan = scan
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

        // The files lean on each other, so a change to one is a reload of
        // all of them.
        let observation = observed.map(\.stamp) + scan.obstructions.map(\.description)

        guard observation != generation else { return currentCatalog }

        // One reload at a time: a caller arriving while one runs waits for
        // it and looks again.
        if let reloading {
            await reloading.value

            return await observing(scan)
        }

        let reload = Task { await self.reload(observed, scan: scan, observation: observation) }

        reloading = reload
        await reload.value
        reloading = nil

        return currentCatalog
    }

    // Every observed file read, loaded and built again, and the entries and
    // failures of this observation put in place.
    private func reload(_ observed: [Observed], scan: StoreScan, observation: [String]) async {
        var ledger = LoadFailureLedger(prior: failureCache)
        let spending = spent(observed, recording: &ledger)
        var candidates = spending.candidates
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

        cache = standing.entries
        compiled = standing.compiled
        failureCache = ledger.fresh
        collisions = freshCollisions
        scanObstructions = scan.obstructions
        collidedNames = Dictionary(
            uniqueKeysWithValues: collided.map { entry in (entry.key, entry.sources) }
        )
        generation = observation
        reading = spending.frontend
    }

    // The observed files read leaning on each other and on the library,
    // each loaded the way a runtime receives a document and held to Forge's
    // convention. What does not read, load or keep the convention is
    // recorded, and a file the convention refuses leans no other: the files
    // are read again without it, so no other file is refused for what it
    // declares.
    private func spent(
        _ observed: [Observed],
        recording ledger: inout LoadFailureLedger
    ) -> (candidates: [(key: String, source: String, value: Entry)], frontend: YAMLFrontend?) {
        var texts: [(observed: Observed, text: String)] = []

        for file in observed {
            do {
                texts.append((file, try String(contentsOf: file.file.url, encoding: .utf8)))
            } catch {
                record(file, refusal: "\(error)", in: &ledger)
            }
        }

        while true {
            let leaning: (frontend: YAMLFrontend, refusals: [Int: any Error])

            do {
                leaning = try ForgeSpec.frontend(leaningOn: texts.map(\.text))
            } catch {
                for (file, _) in texts {
                    record(file, refusal: "\(error)", in: &ledger)
                }

                return ([], nil)
            }

            var candidates: [(key: String, source: String, value: Entry)] = []
            var refusals: [(file: Observed, refusal: String)] = []
            var unconventional: Set<Int> = []

            for (index, (file, text)) in texts.enumerated() {
                if let refusal = leaning.refusals[index] {
                    refusals.append((file, "\(refusal)"))

                    continue
                }

                let base = file.file.url.deletingPathExtension().lastPathComponent

                do {
                    let document = try leaning.frontend.document(from: text)
                    let module = try Loader().load(document, identity: try Identity.of(document))
                    let documentation = try leaning.frontend.documentation(from: text)

                    if let breach = convention(module, named: base, text: text) {
                        ledger.record(
                            source: file.file.source,
                            reason: breach.reason,
                            mtime: file.mtime,
                            stderrLine: "\(breach.line) (\(file.file.source))",
                            name: base
                        )
                        unconventional.insert(index)

                        continue
                    }

                    candidates.append(
                        (
                            base,
                            file.file.source,
                            Entry(
                                name: base,
                                module: module,
                                mtime: file.mtime,
                                source: file.file.source,
                                documentation: documentation
                            )
                        )
                    )
                } catch {
                    refusals.append((file, "\(error)"))
                }
            }

            guard unconventional.isEmpty else {
                texts = texts.indices.filter { index in !unconventional.contains(index) }.map { index in texts[index] }

                continue
            }

            for (file, refusal) in refusals {
                record(file, refusal: refusal, in: &ledger)
            }

            return (candidates, leaning.frontend)
        }
    }

    // Forge's convention on top of the language: a workflow file declares one
    // procedure, names it after the file, and takes a name the library and
    // std do not give, since another workflow calls it by that name. The
    // language lets a module declare many; this is where a workflow says it
    // is one thing you can run by the name you know it by. The breach, where
    // the file makes one.
    private func convention(
        _ module: Warp.Module,
        named base: String,
        text: String
    ) -> (reason: String, line: String)? {
        let declared = module.procedures.keys.map(\.spelling).sorted()

        guard declared == [base], let name = module.procedures.keys.first else {
            return (
                "a workflow file declares exactly one procedure named"
                    + " after the file — expected 'procedures: { \(base): ... }',"
                    + " found \(declared.map { key in "'\(key)'" })",
                "workflow procedure/filename mismatch"
            )
        }

        if let refusal = ForgeSpec.refusal(calling: name, declaredIn: text) {
            return (
                "a workflow is called by its name, and another workflow writing '\(base)' is refused: \(refusal)",
                "workflow named like the vocabulary"
            )
        }

        return nil
    }

    // The entries that build, each compiled against the vocabulary, which
    // is compiled once a process: all of them where they build together,
    // and otherwise each against the entries compiled before it, until a
    // round admits none. An entry left is recorded with its build refusal,
    // and no run links it.
    private func built(
        _ live: [String: Entry],
        recording ledger: inout LoadFailureLedger
    ) async -> (entries: [String: Entry], compiled: [(name: String, compiled: Compiled)]) {
        var pending = live.values.sorted { left, right in left.name < right.name }

        if
            let together = try? await ForgeSpec.compiled(pending.map(\.module)),
            (try? await ForgeSpec.linked(together)) != nil
        {
            return (live, zip(pending, together).map { entry, object in (entry.name, object) })
        }

        var standing: [String: Entry] = [:]
        var compiled: [(name: String, compiled: Compiled)] = []
        var refusals: [String: String] = [:]
        var admitted = true

        while admitted, !pending.isEmpty {
            admitted = false

            for entry in pending {
                do {
                    let own = try await ForgeSpec.compiled([entry.module], beside: compiled.map(\.compiled))

                    _ = try await ForgeSpec.linked(compiled.map(\.compiled) + own)
                    standing[entry.name] = entry
                    compiled += own.map { object in (entry.name, object) }
                    admitted = true
                } catch {
                    refusals[entry.name] = "\(error)"
                }
            }

            pending.removeAll { entry in standing[entry.name] != nil }
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

        return (standing, compiled)
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

