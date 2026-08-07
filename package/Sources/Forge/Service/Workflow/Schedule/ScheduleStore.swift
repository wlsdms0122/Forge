//
//  ScheduleStore.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Yams

actor ScheduleStore {
    struct Entry: Sendable {
        // MARK: - Property
        let schedule: Schedule
        let mtime: Date
        let path: URL
        let source: String
        let runtime: Bool
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct Catalog: Sendable {
        // MARK: - Property
        let entries: [Entry]
        let failures: [LoadFailure]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct TickSnapshot: Sendable {
        // MARK: - Property
        let entries: [Entry]
        let declaredIDs: Set<String>
        let declarationsComplete: Bool
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    enum IDState {
        case live(Entry)
        case collided
        case unknown(reason: String)
        case absent
    }
    
    // MARK: - Property
    let configDir: URL?
    let runtimeDirectory: URL?
    let stateFile: URL
    
    private var cache: [String: Entry] = [:]
    private var enabledIDs: [String: String]
    private var stateFailure: LoadFailure?
    private var failureCache: [String: LoadFailure] = [:]
    private var collisions: [LoadFailure] = []
    private var collidedIDs: Set<String> = []
    private var failedIDs: Set<String> = []
    private var scanIncomplete = false
    
    private var currentCatalog: Catalog {
        Catalog(
            entries: cache.values.map { entry in effective(entry) },
            failures: (
                Array(failureCache.values)
                    + collisions
                    + (stateFailure.map { failure in [failure] } ?? [])
            )
                .sorted { lhs, rhs in lhs.path < rhs.path }
        )
    }
    
    // MARK: - Initializer
    init(configDir: URL?, runtimeDirectory: URL? = nil, stateFile: URL) {
        self.configDir = configDir
        self.runtimeDirectory = runtimeDirectory
        self.stateFile = stateFile
        (self.enabledIDs, self.stateFailure) = Self.loadEnabled(stateFile)
    }
    
    // MARK: - Public
    func ensureRuntimeDirectory() {
        guard let directory = runtimeDirectory else { return }
        
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            FileHandle.standardError.write(Data(
                "forge: runtime schedule directory could not be created (\(directory.path)): \(error) — declarations will read as unobserved\n".utf8))
        }
    }
    
    @discardableResult
    func catalog() async -> Catalog {
        let fileManager = FileManager.default
        
        var byPath: [URL: Entry] = [:]
        
        for entry in cache.values { byPath[entry.path] = entry }
        
        var ledger = LoadFailureLedger(prior: failureCache)
        var candidates: [(key: String, source: String, value: Entry)] = []
        var incomplete = read(
            configDir,
            runtime: false,
            skipping: runtimeDirectory,
            byPath: byPath,
            into: &candidates,
            ledger: &ledger
        )
        incomplete = read(
            runtimeDirectory,
            runtime: true,
            skipping: nil,
            byPath: byPath,
            into: &candidates,
            ledger: &ledger
        ) || incomplete
        
        let (live, collided) = partitionUniqueKeys(candidates)
        collisions = collisionFailures(kind: "schedule id", collided)
        collidedIDs = Set(collided.map(\.key))
        
        for directory in [configDir, runtimeDirectory].compactMap({ directory in directory })
        where fileManager.fileExists(atPath: directory.path) {
            ledger.recordLegacyJSONSpecs(in: directory, kind: "schedule")
        }
        
        failureCache = ledger.fresh
        failedIDs = Set(failureCache.keys.map { source in
            URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
        })
        scanIncomplete = incomplete
        cache = live
        
        return currentCatalog
    }
    
    func all() async -> [Schedule] {
        await catalog().entries.map(\.schedule)
    }
    
    func tickSnapshot() async -> TickSnapshot {
        await catalog()
        
        return TickSnapshot(
            entries: cache.values.map { entry in effective(entry) },
            declaredIDs: Set(cache.keys).union(collidedIDs).union(failedIDs),
            declarationsComplete: !scanIncomplete
        )
    }
    
    func lookup(_ id: String) async -> Schedule? {
        await catalog()
        
        return cache[id].map { entry in effective(entry).schedule }
    }
    
    func setEnabled(id: String, enabled: Bool, authorizedWorkflow: String) async throws {
        let entry = try await requireLive(id)
        try requireIdentity(entry, id: id, authorizedWorkflow: authorizedWorkflow)
        
        var next = enabledIDs
        
        if enabled { next[id] = entry.schedule.workflow } else { next.removeValue(forKey: id) }
        
        guard next != enabledIDs else { return }
        
        try persistEnabled(next)
    }
    
    @discardableResult
    func create(_ requested: Schedule) async throws -> Schedule {
        guard let directory = runtimeDirectory else {
            throw ResolutionError("runtime schedule directory not configured — schedule.create is disabled")
        }
        
        guard isStoreSafeID(requested.id) else {
            throw ProtocolError("schedule id must match [A-Za-z0-9._-] with no leading dot: '\(requested.id)'")
        }
        
        let schedule = requested.withID(ScheduleIDSpace.stamp(requested.id))
        
        switch await observedIDState(schedule.id) {
        case .absent:
            break
        
        case .live:
            throw ProtocolError("schedule id already exists: '\(schedule.id)'")
        
        case .collided:
            throw ProtocolError(
                "schedule id '\(schedule.id)' collides across multiple definition files — resolve the collision (see schedule.list failures) before creating")
        
        case .unknown(let reason):
            throw ProtocolError(
                "cannot prove schedule id '\(schedule.id)' is unused — \(reason); retry after resolving")
        }
        
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(
            schedule,
            to: directory.appendingPathComponent("\(schedule.id).\(specFileExtension)")
        )
        
        if schedule.enabled {
            var next = enabledIDs
            next[schedule.id] = schedule.workflow
            
            do {
                try persistEnabled(next)
            } catch {
                throw ProtocolError(
                    "schedule '\(schedule.id)' created but enabling failed (\(error)) — it stays disabled; retry with schedule.set_enabled")
            }
        }
        
        return schedule
    }
    
    func delete(id: String, authorizedWorkflow: String? = nil) async throws {
        let entry = try await requireLive(id)
        
        if let authorizedWorkflow {
            try requireIdentity(entry, id: id, authorizedWorkflow: authorizedWorkflow)
        }
        
        try FileManager.default.removeItem(at: entry.path)
        cache.removeValue(forKey: id)
        
        if enabledIDs[id] != nil {
            var next = enabledIDs
            next.removeValue(forKey: id)
            
            do {
                try persistEnabled(next)
            } catch {
                FileHandle.standardError.write(Data(
                    "forge: schedule enabled-ledger prune failed (\(id)): \(error)\n".utf8))
            }
        }
    }
    
    // MARK: - Private
    private func read(
        _ directory: URL?,
        runtime: Bool,
        skipping nested: URL?,
        byPath: [URL: Entry],
        into candidates: inout [(key: String, source: String, value: Entry)],
        ledger: inout LoadFailureLedger
    ) -> Bool {
        guard let directory else { return false }
        // A directory that does not exist yet is a definitively empty
        // declaration set — nothing in it can be unobserved. Only an existing
        // directory that fails enumeration makes the scan incomplete.
        guard FileManager.default.fileExists(atPath: directory.path) else { return false }
        
        let nestedPath = nested?.standardizedFileURL.path
        let scan = scanStoreFiles(in: directory, pathExtension: specFileExtension)
        var incomplete = !scan.isComplete
        
        for file in scan.files {
            if let nestedPath,
                file.url.standardizedFileURL.path.hasPrefix(nestedPath + "/") {
                continue
            }
            
            incomplete = loadFile(
                file,
                runtime: runtime,
                byPath: byPath,
                into: &candidates,
                ledger: &ledger
            ) || incomplete
        }
        
        return incomplete
    }
    
    @discardableResult
    private func loadFile(
        _ file: ScannedFile,
        runtime: Bool,
        byPath: [URL: Entry],
        into candidates: inout [(key: String, source: String, value: Entry)],
        ledger: inout LoadFailureLedger
    ) -> Bool {
        let fileManager = FileManager.default
        let url = file.url
        
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
            let mtime = attributes[.modificationDate] as? Date
        else {
            ledger.record(
                source: file.source,
                reason: "file attributes unavailable — declaration unreadable this reload",
                mtime: .distantPast,
                stderrLine: "schedule file attributes unavailable (\(file.source))"
            )
            
            return false
        }
        
        if let existing = byPath[url], existing.mtime == mtime {
            candidates.append((existing.schedule.id, file.source, existing))
            
            return false
        }
        
        if ledger.reuse(source: file.source, mtime: mtime) { return false }
        
        do {
            let data = try Data(contentsOf: url)
            var schedule = try YAMLSpec.decode(Schedule.self, from: data)
            let base = url.deletingPathExtension().lastPathComponent
            
            if schedule.id.isEmpty { schedule = schedule.withID(base) }
            
            guard schedule.id == base else {
                ledger.record(
                    source: file.source,
                    reason: "schedule id '\(schedule.id)' must equal the file basename '\(base)' — identity is the filename (rename the file or drop the id from the body)",
                    mtime: mtime,
                    stderrLine: "schedule id/filename mismatch (\(file.source)): id '\(schedule.id)' vs basename '\(base)'"
                )
                
                return false
            }
            
            if let violation = ScheduleIDSpace.violation(id: schedule.id, runtime: runtime) {
                ledger.record(
                    source: file.source,
                    reason: violation,
                    mtime: mtime,
                    stderrLine: "schedule id namespace violation (\(file.source)): \(violation)"
                )
                
                return false
            }
            
            candidates.append((
                schedule.id,
                file.source,
                Entry(
                    schedule: schedule,
                    mtime: mtime,
                    path: url,
                    source: file.source,
                    runtime: runtime
                )
            ))
        } catch {
            ledger.record(
                source: file.source,
                reason: "\(error)",
                mtime: mtime,
                stderrLine: "schedule load failed (\(file.source)): \(error)"
            )
        }
        
        return false
    }
    
    private func observedIDState(_ id: String) async -> IDState {
        await catalog()
        
        if let entry = cache[id] { return .live(entry) }
        if collidedIDs.contains(id) { return .collided }
        
        if failedIDs.contains(id) {
            return .unknown(
                reason: "declaration file for '\(id)' exists but failed to load (see schedule.list failures)"
            )
        }
        
        if scanIncomplete {
            return .unknown(
                reason: "declaration set could not be fully enumerated this reload (directory unobservable)"
            )
        }
        
        return .absent
    }
    
    private func requireLive(_ id: String) async throws -> Entry {
        switch await observedIDState(id) {
        case .live(let entry):
            return entry
        
        case .collided:
            throw ProtocolError(
                "schedule id '\(id)' collides across multiple definition files — resolve the collision (see schedule.list failures) before mutating")
        
        case .unknown(let reason):
            throw ProtocolError("schedule '\(id)' state unknown — \(reason); retry after resolving")
        
        case .absent:
            throw ResolutionError("schedule not found: \(id)")
        }
    }
    
    private func requireIdentity(
        _ entry: Entry,
        id: String,
        authorizedWorkflow: String
    ) throws {
        guard entry.schedule.workflow == authorizedWorkflow else {
            throw ProtocolError(
                "schedule '\(id)' now points at workflow '\(entry.schedule.workflow)' (authorized against '\(authorizedWorkflow)') — the definition changed underneath; re-read and retry")
        }
    }
    
    private func effective(_ entry: Entry) -> Entry {
        let isEnabled = enabledIDs[entry.schedule.id] == entry.schedule.workflow
        
        guard entry.schedule.enabled != isEnabled else { return entry }
        
        return Entry(
            schedule: entry.schedule.withEnabled(isEnabled),
            mtime: entry.mtime,
            path: entry.path,
            source: entry.source,
            runtime: entry.runtime
        )
    }
    
    private func persistEnabled(_ next: [String: String]) throws {
        try Self.writeEnabled(next, to: stateFile)
        enabledIDs = next
        stateFailure = nil
    }
    
    private func write(_ schedule: Schedule, to url: URL) throws {
        let data = try JSONEncoder().encode(schedule)
        var object = try JSONSerialization.jsonObject(with: data)
        
        if var dictionary = object as? [String: Any] {
            dictionary.removeValue(forKey: "id")
            object = dictionary
        }
        
        let text = try Yams.serialize(node: Self.quotedNode(from: object))
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(
                ".\(url.lastPathComponent).tmp-\(UUID().uuidString.prefix(8))"
            )
        
        try Data(text.utf8).write(to: temporary)
        
        do {
            try FileManager.default.moveItem(at: temporary, to: url)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            
            if FileManager.default.fileExists(atPath: url.path) {
                throw ProtocolError(
                    "schedule file '\(url.lastPathComponent)' already exists — refusing to overwrite an existing declaration")
            }
            
            throw error
        }
    }
    
    private static func quotedNode(from any: Any) throws -> Node {
        switch any {
        case let dictionary as [String: Any]:
            let pairs = try dictionary
                .sorted { lhs, rhs in lhs.key < rhs.key }
                .map { pair in
                    (Node(pair.key, Tag(.str), .doubleQuoted), try quotedNode(from: pair.value))
                }
            
            return Node(pairs, Tag(.map))
        
        case let array as [Any]:
            return Node(try array.map(quotedNode(from:)), Tag(.seq))
        
        case let string as String:
            return Node(string, Tag(.str), .doubleQuoted)
        
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return Node(number.boolValue ? "true" : "false")
            }
            
            return Node("\(number)")
        
        case is NSNull:
            return Node("null")
        
        default:
            throw ProtocolError("unrepresentable value in schedule serialization: \(type(of: any))")
        }
    }
    
    private static func writeEnabled(_ ids: [String: String], to path: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: ids,
            options: [.sortedKeys, .prettyPrinted]
        )
        
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: path, options: .atomic)
    }
    
    private static func loadEnabled(_ path: URL) -> ([String: String], LoadFailure?) {
        let data: Data
        
        do {
            data = try Data(contentsOf: path)
        } catch {
            if !FileManager.default.fileExists(atPath: path.path) { return ([:], nil) }
            
            return ([:], surfaceLedgerFailure(path, "unreadable: \(error)", quarantining: nil))
        }
        
        guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] else {
            let quarantine = path.deletingLastPathComponent().appendingPathComponent(
                path.lastPathComponent + ".corrupt-\(UInt64(Date().timeIntervalSince1970))"
            )
            let moved = (try? FileManager.default.moveItem(at: path, to: quarantine)) != nil
            
            return ([:], surfaceLedgerFailure(
                path,
                "unparseable — expected a JSON {id: workflow} object",
                quarantining: moved ? quarantine.lastPathComponent : nil
            ))
        }
        
        return (raw, nil)
    }
    
    private static func surfaceLedgerFailure(
        _ path: URL,
        _ reason: String,
        quarantining quarantine: String?
    ) -> LoadFailure {
        let suffix = quarantine.map { name in " (preserved as '\(name)')" } ?? ""
        
        FileHandle.standardError.write(Data(
            "forge: schedule enabled-ledger '\(path.path)' \(reason)\(suffix) — treating every schedule as disabled until the ledger is rewritten\n".utf8))
        
        return LoadFailure(
            path: path.lastPathComponent,
            reason: "enabled-ledger \(reason)\(suffix)",
            mtime: .distantPast
        )
    }
}
