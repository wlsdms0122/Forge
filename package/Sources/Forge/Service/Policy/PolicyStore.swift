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
    
    // MARK: - Property
    let directory: URL?
    
    private var files: SpecDirectory<[String: [String]]>?
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
        self.files = directory.map { directory in SpecDirectory(directory: directory, kind: "policy") }
    }
    
    init(seed: [String: [String]]) {
        self.directory = nil
        self.merged = seed
    }
    
    // MARK: - Public
    @discardableResult
    func catalog() async -> Catalog {
        guard var files else { return currentCatalog }
        
        var ledger = LoadFailureLedger(prior: failureCache)
        let reading = files.read(recording: &ledger) { _, data in
            try YAMLSpec.decode([String: [String]].self, from: data)
        }
        
        self.files = files
        scanFailures = reading.obstructions.map { obstruction in
            LoadFailure(
                path: "<scan>",
                reason: "policy directory scan incomplete — \(obstruction.description)",
                mtime: .distantPast
            )
        }
        scanFailures += reading.unreadable.map { file in
            LoadFailure(
                path: file.source,
                reason: "policy file metadata could not be read — grants from this file"
                    + " are not merged this reload",
                mtime: .distantPast
            )
        }
        failureCache = ledger.fresh
        FileHandle.standardError.write(Data(ledger.announcement.utf8))
        
        var invalid: [LoadFailure] = []
        var accumulated: [String: Set<String>] = [:]
        
        for loaded in reading.loaded {
            let source = loaded.file.file.url.lastPathComponent
            
            for (principal, workflows) in loaded.value {
                guard Principal.isValidPattern(principal) else {
                    invalid.append(
                        LoadFailure(
                            path: source,
                            reason: "principal pattern '\(principal)' is outside the match"
                                + " grammar (`*`, exact, `<class>:*`) — this grant can never"
                                + " match and was excluded",
                            mtime: loaded.file.mtime
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
                                mtime: loaded.file.mtime
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
