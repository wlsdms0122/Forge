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

// The workflow catalog, with the same scan and failure-ledger discipline as
// the other stores. At a reload every file is read by the YAML front end
// leaning on the library and on the other files, loaded as a document and
// built against what builds; a file that does not is a failure, and the
// entries are the files that built. Identity is the file basename, and the
// file declares one procedure under it.
actor WorkflowCatalog {
    struct Snapshot: Sendable {
        // MARK: - Property
        let entries: [(workflow: Workflow, source: String)]
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
        let source: String

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    // The name an inline spec's one procedure is declared under.
    static let inlineSigil = "<inline>"

    let directory: URL?

    // What the workflows are written over, which every run of one links.
    let vocabulary: ForgeVocabulary

    private let builder: WorkflowBuilder
    private var cache: [String: Entry] = [:]
    private var failureCache: [String: LoadFailure] = [:]
    private var collisions: [LoadFailure] = []
    private var collidedNames: [String: [String]] = [:]
    private var scanObstructions: [StoreScan.Obstruction] = []

    // The observation the entries and failures were read from: each file
    // with its modification time, and what the scan could not see.
    private var generation: [String]?

    // The reload in progress, which a caller arriving during it waits for.
    private var reloading: Task<String, Never>?

    // The front end the files of this observation were read with, leaning on
    // the library and on them.
    private var reading: YAMLFrontend?

    // The files that built, each compiled once a reload, in the order they
    // were compiled, and the image the reload linked them into, which a run
    // of one of them runs.
    private var compiled: [(name: String, compiled: Compiled)] = []
    private var image: Image?

    private var currentSnapshot: Snapshot {
        let scanFailures = scanObstructions.map { obstruction in obstruction.failure(kind: "workflow") }

        return Snapshot(
            entries: cache.values
                .map { entry in (entry.workflow, entry.source) }
                .sorted { left, right in left.workflow.name < right.workflow.name },
            failures: (Array(failureCache.values) + collisions + scanFailures)
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
    // The directory, the daemon's, reloaded where it changed and answered
    // as a snapshot: a reload announces on stderr each failure new to it.
    @discardableResult
    func reload() async -> Snapshot {
        guard let directory else {
            cache.removeAll()
            failureCache.removeAll()
            collisions.removeAll()
            collidedNames.removeAll()
            scanObstructions.removeAll()
            generation = nil
            reading = nil
            compiled.removeAll()
            image = nil

            return currentSnapshot
        }

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory.path) else {
            scanObstructions = [
                .init(
                    scope: "",
                    reason: "configured workflow directory is not visible (\(directory.path))"
                )
            ]

            return currentSnapshot
        }

        let observed = await observing(StoreScan(directory: directory, pathExtension: StoreScan.specFileExtension))

        FileHandle.standardError.write(Data(observed.announcement.utf8))

        return observed.snapshot
    }

    // The files at these paths read the way a reload reads the directory's,
    // for a gate that admits what the daemon admits and reports what it
    // records.
    func reload(of paths: [String]) async -> Snapshot {
        await observing(
            StoreScan(files: paths.map { path in ScannedFile(url: URL(fileURLWithPath: path), source: path) })
        )
        .snapshot
    }

    // An inline spec: one procedure written in the YAML notation, read the
    // way a catalog file is, leaning on the library and on the catalog's
    // files, and declared public under the inline sigil, which a run starts
    // from.
    func inline(_ spec: JSONValue) async throws -> Workflow {
        guard case var .object(procedure) = spec else {
            throw WorkflowValidationError("an inline spec is one procedure, written as an object")
        }

        procedure["access"] = .string("public")

        let text = try JSONEncoder().encode(
            JSONValue.object(["procedures": .object([Self.inlineSigil: .object(procedure)])])
        )

        await reload()

        let document: Value

        // The caller wrote an object and no text, so a refusal names its
        // place in the document and not a line of the text written here.
        do {
            document = try (reading ?? vocabulary.frontend).document(from: text)
        } catch let refusal as AuthoringError {
            throw refusal.refusal
        }

        return try Workflow(
            name: Self.inlineSigil,
            module: try Loader().load(document, identity: try Identity.of(document)),
            documentation: nil
        )
    }

    // The image a run of this module runs: for a file of the catalog, the
    // one the reload linked; for another module, an inline spec, the module
    // compiled against every file that built, as each was compiled at the
    // reload, and the vocabulary compiled once, and linked beside
    // them, a file declaring the name it runs by left out, since the
    // caller's is the one meant.
    func image(running module: Warp.Module, entry: Name) async throws -> Image {
        await reload()

        let standing = compiled
        let files = cache

        if let file = files[entry.spelling], file.workflow.module.identity == module.identity, let image {
            return image
        }

        let world = standing
            .filter { file in files[file.name]?.workflow.module.procedures[entry] == nil }
            .map(\.compiled)

        return try await builder.linked(world + builder.compiled([module], beside: world))
    }

    func resolve(_ name: String) async -> Lookup {
        await reload()

        if let entry = cache[name] { return .found(entry.workflow) }

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
    // The snapshot of the files a scan saw, reloaded where any of them
    // changed since the observation the entries were read from, and what
    // the reload announces, nothing where this call ran none.
    private func observing(_ scan: StoreScan) async -> (snapshot: Snapshot, announcement: String) {
        var scan = scan
        let observed = scan.observe()


        // The files lean on each other, so a change to one is a reload of
        // all of them.
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

    // Every observed file read, loaded and built again, and the entries and
    // failures of this observation put in place; what is announced for the
    // failures new to it.
    private func reload(_ observed: [ObservedFile], scan: StoreScan, observation: [String]) async -> String {
        var ledger = LoadFailureLedger(prior: failureCache)
        let spending = spent(observed, recording: &ledger)
        var candidates = spending.candidates
        let observedSources = Set(observed.map(\.file.source))

        func isUnobserved(_ source: String) -> Bool {
            !observedSources.contains(source) && scan.isUnobserved(source: source)
        }

        for entry in cache.values where isUnobserved(entry.source) {
            candidates.append((entry.workflow.name, entry.source, entry))
        }

        for (source, failure) in failureCache where isUnobserved(source) {
            _ = ledger.reuse(source: source, mtime: failure.mtime)
        }

        let partition = KeyPartition(candidates)
        var live = partition.live
        var collided = partition.collisions

        for (key, sources) in collidedNames where sources.contains(where: isUnobserved) {
            live.removeValue(forKey: key)

            if !collided.contains(where: { collision in collision.key == key }) {
                collided.append(KeyCollision(key: key, sources: sources))
            }
        }

        let freshCollisions = collided.flatMap { collision in
            collision.failures(kind: "workflow name", standing: collisions, recording: &ledger)
        }
        let standing = await built(live, recording: &ledger)

        cache = standing.entries
        compiled = standing.compiled
        image = standing.image
        failureCache = ledger.fresh
        collisions = freshCollisions
        scanObstructions = scan.obstructions
        collidedNames = Dictionary(
            uniqueKeysWithValues: collided.map { collision in (collision.key, collision.sources) }
        )
        generation = observation
        reading = spending.frontend

        return ledger.announcement
    }

    // The observed files read leaning on each other and on the library,
    // each loaded the way a runtime receives a document and held to Forge's
    // convention. What does not read, load or keep the convention is
    // recorded, and a file the convention refuses leans no other: the files
    // are read again without it, so no other file is refused for what it
    // declares.
    private func spent(
        _ observed: [ObservedFile],
        recording ledger: inout LoadFailureLedger
    ) -> (candidates: [(key: String, source: String, value: Entry)], frontend: YAMLFrontend?) {
        var texts: [(observed: ObservedFile, text: String)] = []

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
                leaning = try builder.frontend(leaningOn: texts.map(\.text))
            } catch {
                for (file, _) in texts {
                    record(file, refusal: "\(error)", in: &ledger)
                }

                return ([], nil)
            }

            var candidates: [(key: String, source: String, value: Entry)] = []
            var refusals: [(file: ObservedFile, refusal: String)] = []
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

                    if let breach = convention(module, named: base) {
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
                                workflow: try Workflow(name: base, module: module, documentation: documentation),
                                mtime: file.mtime,
                                source: file.file.source
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
    // procedure, names it after the file, and takes a name that shadows
    // nothing the library, std and the notation give, since another workflow
    // calls it by that name. The language lets a module declare many; this is
    // where a workflow says it is one thing you can run by the name you know
    // it by. The breach, where the file makes one.
    private func convention(
        _ module: Warp.Module,
        named base: String
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

        if let shadowed = vocabulary.frontend.shadowing(name, as: .procedure) {
            return (
                "a workflow is called by its name, and one named so shadows what the library, std or the notation"
                    + " give: \(shadowed)",
                "workflow named like the vocabulary"
            )
        }

        return nil
    }

    // The entries that build, each compiled against the vocabulary, which
    // is compiled once: all of them where they build together,
    // and otherwise each against the entries compiled before it, until a
    // round admits none. An entry left is recorded with its build refusal,
    // and no run links it. The image is the last link that admitted, which
    // holds every entry admitted.
    private func built(
        _ live: [String: Entry],
        recording ledger: inout LoadFailureLedger
    ) async -> (entries: [String: Entry], compiled: [(name: String, compiled: Compiled)], image: Image?) {
        var pending = live.values.sorted { left, right in left.workflow.name < right.workflow.name }

        if
            let together = try? await builder.compiled(pending.map(\.workflow.module)),
            let image = try? await builder.linked(together)
        {
            return (live, zip(pending, together).map { entry, object in (entry.workflow.name, object) }, image)
        }

        var standing: [String: Entry] = [:]
        var compiled: [(name: String, compiled: Compiled)] = []
        var image: Image?
        var refusals: [String: String] = [:]
        var admitted = true

        while admitted, !pending.isEmpty {
            admitted = false

            for entry in pending {
                do {
                    let own = try await builder.compiled([entry.workflow.module], beside: compiled.map(\.compiled))

                    image = try await builder.linked(compiled.map(\.compiled) + own)
                    standing[entry.workflow.name] = entry
                    compiled += own.map { object in (entry.workflow.name, object) }
                    admitted = true
                } catch {
                    refusals[entry.workflow.name] = "\(error)"
                }
            }

            pending.removeAll { entry in standing[entry.workflow.name] != nil }
        }

        for entry in pending {
            ledger.record(
                source: entry.source,
                reason: "build: \(refusals[entry.workflow.name] ?? "refused")",
                mtime: entry.mtime,
                stderrLine: "workflow build failed (\(entry.source)): \(refusals[entry.workflow.name] ?? "refused")",
                name: entry.workflow.name
            )
        }

        return (standing, compiled, image)
    }

    private func record(_ file: ObservedFile, refusal: String, in ledger: inout LoadFailureLedger) {
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
extension WorkflowCatalog {
    func workflow(named name: String) async throws -> Workflow {
        switch await resolve(name) {
        case let .found(workflow):
            return workflow

        case let .invalid(reason):
            throw WorkflowValidationError("workflow '\(name)' is broken — \(reason)")

        case let .unobserved(reason):
            throw CatalogIncomplete("workflow '\(name)' could not be resolved — \(reason)")

        case .missing:
            throw WorkflowNotFound("workflow not found: \(name)")
        }
    }

    // The workflows that built, without the vocabulary a link adds.
    func modules() async -> [Warp.Module] {
        await reload().entries.map(\.workflow.module)
    }
}

