//
//  PolicyStore.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Yams

actor PolicyStore {
    struct Catalog: Sendable {
        // MARK: - Property
        let policy: [String: [String]]
        let failures: [LoadFailure]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    private struct Entry {
        // MARK: - Property
        let mappings: [String: [String]]
        let mtime: Date
        let path: URL
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    let directory: URL?
    
    private var cache: [URL: Entry] = [:]
    private var merged: [String: [String]] = [:]
    private var failureCache: [String: LoadFailure] = [:]
    private var patternFailures: [LoadFailure] = []
    private var scanFailures: [LoadFailure] = []
    
    private var currentCatalog: Catalog {
        Catalog(
            policy: merged,
            failures: (Array(failureCache.values) + patternFailures + scanFailures)
                .sorted { left, right in left.path < right.path }
        )
    }
    
    // MARK: - Initializer
    init(directory: URL?) {
        self.directory = directory
    }
    
    init(seed: [String: [String]]) {
        self.directory = nil
        self.merged = seed
    }
    
    // MARK: - Public
    @discardableResult
    func catalog() async -> Catalog {
        guard let directory else { return currentCatalog }
        
        guard FileManager.default.fileExists(atPath: directory.path) else {
            cache.removeAll()
            merged.removeAll()
            failureCache.removeAll()
            patternFailures.removeAll()
            scanFailures.removeAll()
            
            return currentCatalog
        }
        
        let fileManager = FileManager.default
        var ledger = LoadFailureLedger(prior: failureCache)
        var fresh: [URL: Entry] = [:]
        
        let scan = scanStoreFiles(in: directory, pathExtension: specFileExtension)
        scanFailures = scan.obstructions.map { obstruction in
            LoadFailure(
                path: "<scan>",
                reason: "policy directory scan incomplete — \(obstruction.description)",
                mtime: .distantPast
            )
        }
        
        for file in scan.files {
            let url = file.url
            
            guard
                let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                let mtime = attributes[.modificationDate] as? Date
            else {
                scanFailures.append(
                    LoadFailure(
                        path: file.source,
                        reason: "policy file metadata could not be read — grants from this file"
                            + " are not merged this reload",
                        mtime: .distantPast
                    )
                )
                
                continue
            }
            
            if let existing = cache[url], existing.mtime == mtime {
                fresh[url] = existing
                
                continue
            }
            
            if ledger.reuse(source: file.source, mtime: mtime) { continue }
            
            do {
                let data = try Data(contentsOf: url)
                let mappings = try YAMLSpec.decode([String: [String]].self, from: data)
                fresh[url] = Entry(mappings: mappings, mtime: mtime, path: url)
            } catch {
                ledger.record(
                    source: file.source,
                    reason: "\(error)",
                    mtime: mtime,
                    stderrLine: "policy load failed (\(file.source)): \(error)"
                )
            }
        }
        
        cache = fresh
        ledger.recordLegacyJSONSpecs(in: directory, kind: "policy")
        failureCache = ledger.fresh
        
        var invalid: [LoadFailure] = []
        var accumulated: [String: Set<String>] = [:]
        
        for entry in fresh.values {
            let source = entry.path.lastPathComponent
            
            for (principal, workflows) in entry.mappings {
                guard Principal.isValidPattern(principal) else {
                    invalid.append(
                        LoadFailure(
                            path: source,
                            reason: "principal pattern '\(principal)' is outside the match"
                                + " grammar (`*`, exact, `<class>:*`) — this grant can never"
                                + " match and was excluded",
                            mtime: entry.mtime
                        )
                    )
                    
                    continue
                }
                
                var accepted: Set<String> = []
                
                for workflowPattern in workflows {
                    if WorkflowPattern.isValidPattern(workflowPattern) {
                        accepted.insert(workflowPattern)
                    } else {
                        invalid.append(
                            LoadFailure(
                                path: source,
                                reason: "workflow pattern '\(workflowPattern)' (principal"
                                    + " '\(principal)') is outside the match grammar (`*`,"
                                    + " exact, trailing `*`) — this grant can never match and"
                                    + " was excluded",
                                mtime: entry.mtime
                            )
                        )
                    }
                }
                
                if !accepted.isEmpty { accumulated[principal, default: []].formUnion(accepted) }
            }
        }
        
        patternFailures = invalid.sorted { left, right in left.reason < right.reason }
        merged = accumulated.mapValues { patterns in Array(patterns).sorted() }
        
        return currentCatalog
    }
    
    func allows(principal: String, workflow: String) async -> Bool {
        await catalog()
        
        for (principalPattern, workflowPatterns) in merged {
            guard
                Principal.matches(pattern: principalPattern, principal: principal)
            else {
                continue
            }
            
            for workflowPattern in workflowPatterns {
                if WorkflowPattern.matches(pattern: workflowPattern, name: workflow) {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Private
}
