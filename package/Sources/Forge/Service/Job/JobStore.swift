//
//  JobStore.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

actor JobStore {
    struct Entry: Sendable {
        // MARK: - Property
        let job: Job
        let mtime: Date
        let path: URL
        let source: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    let directory: URL?
    
    private var cache: [String: Entry] = [:]
    private var failedIDs: Set<String> = []
    private var scanIncomplete = false
    
    // MARK: - Initializer
    init(directory: URL?) {
        self.directory = directory
    }
    
    // MARK: - Public
    func reload() async {
        let fileManager = FileManager.default
        var byPath: [URL: Entry] = [:]
        
        for entry in cache.values { byPath[entry.path] = entry }
        
        var fresh: [String: Entry] = [:]
        let decoder = JSONDecoder()
        
        guard let directory else {
            cache = [:]
            failedIDs = []
            scanIncomplete = false
            
            return
        }
        
        // A directory that does not exist yet is a definitively empty store —
        // there is nothing unobserved in it. Only an existing directory that
        // cannot be fully enumerated makes the scan incomplete.
        guard fileManager.fileExists(atPath: directory.path) else {
            cache = [:]
            failedIDs = []
            scanIncomplete = false

            return
        }
        
        var failed: Set<String> = []
        var scan = scanStoreFiles(in: directory, pathExtension: "json")
        var observedPaths: Set<URL> = []
        
        for file in scan.files {
            let url = file.url
            
            guard
                let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                let mtime = attributes[.modificationDate] as? Date
            else {
                scan.obstructions.append(
                    .init(scope: file.source, reason: "job file metadata could not be read")
                )
                
                FileHandle.standardError.write(
                    Data(
                        ("forge: job metadata unreadable (\(file.source))"
                            + " — treating as unobserved\n").utf8
                    )
                )
                
                continue
            }
            
            observedPaths.insert(url)
            
            if let existing = byPath[url], existing.mtime == mtime {
                fresh[existing.job.id] = existing
                
                continue
            }
            
            do {
                let data = try Data(contentsOf: url)
                let job = try decoder.decode(Job.self, from: data)
                fresh[job.id] = Entry(job: job, mtime: mtime, path: url, source: file.source)
            } catch {
                failed.insert(url.deletingPathExtension().lastPathComponent)
                
                FileHandle.standardError.write(
                    Data("forge: job load failed (\(file.source)): \(error)\n".utf8)
                )
            }
        }
        
        if !scan.isComplete {
            for (id, entry) in cache where fresh[id] == nil && !observedPaths.contains(entry.path) {
                fresh[id] = entry
            }
        }
        
        cache = fresh
        failedIDs = failed
        scanIncomplete = !scan.isComplete
    }
    
    func all() async -> [Job] {
        await reload()
        
        return cache.values.map(\.job)
    }
    
    func allEntries() async -> [Entry] {
        await reload()
        
        return Array(cache.values)
    }
    
    func lookup(_ id: String) async -> Job? {
        await reload()
        
        return cache[id]?.job
    }
    
    func create(_ job: Job) async throws {
        guard let directory else {
            throw ResolutionError("job directory not configured — job.create is disabled")
        }
        
        guard isStoreSafeID(job.id) else {
            throw ProtocolError(
                "job id must match [A-Za-z0-9._-] with no leading dot: '\(job.id)'"
            )
        }
        
        await reload()
        
        if cache[job.id] != nil {
            throw ProtocolError("job id already exists: '\(job.id)'")
        }
        
        if failedIDs.contains(job.id) {
            throw ProtocolError(
                "job file for '\(job.id)' exists but failed to load — refusing to overwrite;"
                    + " inspect or remove the file first"
            )
        }
        
        if scanIncomplete {
            throw ProtocolError(
                "job directory could not be fully enumerated — refusing to create '\(job.id)'"
                    + " while an existing ticket may be unobserved; retry once the directory"
                    + " is readable"
            )
        }
        
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        
        let url = directory.appendingPathComponent("\(job.id).json")
        
        try write(job, to: url)
        
        cacheEntry(job, at: url, source: "ephemeral")
    }
    
    func delete(id: String) async throws {
        await reload()
        
        guard let entry = cache[id] else {
            throw missingReason(id)
        }
        
        try FileManager.default.removeItem(at: entry.path)
        cache.removeValue(forKey: id)
        
        if let parentID = entry.job.parentJob {
            await bestEffort(
                id: parentID,
                by: nil,
                consequence: "deleted child '\(id)' left back-linked"
            ) { job in
                job.children.removeAll { child in child == id }
            }
        }
        
        for childID in entry.job.children {
            await bestEffort(
                id: childID,
                by: nil,
                consequence: "deleted parent '\(id)' left referenced by parent_job"
            ) { job in
                if job.parentJob == id { job.parentJob = nil }
            }
        }
    }
    
    @discardableResult
    func update(
        id: String,
        by: String? = nil,
        stamp: Bool = true,
        _ mutate: (inout Job) -> Void
    ) async throws -> Job {
        guard directory != nil else {
            throw JobStoreError.notConfigured
        }
        
        await reload()
        
        guard let entry = cache[id] else {
            throw missingReason(id)
        }
        
        var job = entry.job
        mutate(&job)
        
        if stamp { job.updatedAt = nowISO() }
        if let by { job.updatedBy = by }
        
        try write(job, to: entry.path)
        cacheEntry(job, at: entry.path, source: entry.source)
        
        return job
    }
    
    func addComment(id: String, by: String?, note: String) async throws {
        let comment = Job.Comment(ts: nowISO(), by: by, note: note)
        
        _ = try await update(id: id, by: by) { job in job.comments.append(comment) }
    }
    
    func setStatus(id: String, by: String?, _ status: String) async throws {
        _ = try await update(id: id, by: by) { job in job.status = status }
    }
    
    func setBrief(id: String, by: String?, _ brief: String) async throws {
        _ = try await update(id: id, by: by) { job in job.brief = brief }
    }
    
    func appendRef(id: String, by: String?, ref: String, note: String?) async throws {
        _ = try await update(id: id, by: by) { job in
            if let index = job.refs.firstIndex(where: { existing in existing.ref == ref }) {
                if let note { job.refs[index].note = note }
            } else {
                job.refs.append(Job.Ref(ref: ref, note: note))
            }
        }
    }
    
    func setPlanItem(
        id: String,
        by: String?,
        item: Int,
        desc: String?,
        status: String
    ) async throws {
        _ = try await update(id: id, by: by) { job in
            job.plan.upsert(id: item, desc: desc, status: status)
        }
    }
    
    func appendEvent(
        id: String,
        kind: Job.Event.Kind,
        run: String? = nil,
        detail: String? = nil
    ) async {
        let event = Job.Event(
            ts: nowISO(),
            kind: kind,
            run: run,
            detail: detail.map { detail in String(detail.prefix(300)) }
        )
        
        await bestEffort(
            id: id,
            by: nil,
            stamp: false,
            consequence: "lifecycle fact (\(kind.rawValue)) lost (ticket left without a reason)"
        ) { job in
            job.events.append(event)
        }
    }
    
    func recordTouch(id: String, run: String, via: String) async {
        let timestamp = nowISO()
        
        await bestEffort(
            id: id,
            by: nil,
            stamp: false,
            consequence: "attachment observation (run_attached) lost"
        ) { job in
            guard !job.openRuns.contains(run) else { return }
            
            job.events.append(
                Job.Event(ts: timestamp, kind: .runAttached, run: run, detail: via)
            )
        }
    }
    
    func closeRun(run: String, failure: String?) async {
        for job in await all() where job.openRuns.contains(run) {
            await appendEvent(
                id: job.id,
                kind: failure == nil ? .runCompleted : .runFailed,
                run: run,
                detail: failure
            )
        }
    }
    
    func closeOrphans() async {
        for job in await all() {
            for run in job.openRuns {
                await appendEvent(
                    id: job.id,
                    kind: .runOrphaned,
                    run: run.isEmpty ? nil : run,
                    detail: "unclosed at daemon start"
                )
            }
        }
    }
    
    func addChild(parentID: String, childID: String, by: String?, note: String?) async {
        let comment = note.map { note in Job.Comment(ts: nowISO(), by: by, note: note) }
        
        await bestEffort(
            id: parentID,
            by: by,
            consequence: "parent back-link (child '\(childID)') missing"
        ) { job in
            if !job.children.contains(childID) { job.children.append(childID) }
            if let comment { job.comments.append(comment) }
        }
    }
    
    // MARK: - Private
    private func bestEffort(
        id: String,
        by: String?,
        stamp: Bool = true,
        consequence: String,
        _ mutate: (inout Job) -> Void
    ) async {
        do {
            _ = try await update(id: id, by: by, stamp: stamp, mutate)
        } catch JobStoreError.notFound, JobStoreError.notConfigured {
        } catch {
            FileHandle.standardError.write(
                Data(
                    "forge: job '\(id)' persist failed — \(consequence): \(error)\n".utf8
                )
            )
        }
    }
    
    private func missingReason(_ id: String) -> JobStoreError {
        if
            let directory,
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("\(id).json").path
            )
        {
            return .unreadable(id)
        }
        
        return .notFound(id)
    }
    
    private func write(_ job: Job, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        
        let data = try encoder.encode(job)
        
        try data.write(to: url, options: .atomic)
    }
    
    private func cacheEntry(_ job: Job, at url: URL, source: String) {
        let mtime = (
            (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate]
                as? Date
        ) ?? Date()
        
        cache[job.id] = Entry(job: job, mtime: mtime, path: url, source: source)
    }
    
    private func nowISO() -> String { ISO8601.string(Date()) }
}
