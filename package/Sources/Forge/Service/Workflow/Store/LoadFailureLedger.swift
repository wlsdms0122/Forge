//
//  LoadFailureLedger.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct LoadFailureLedger {
    // MARK: - Property
    private let prior: [String: LoadFailure]
    
    private(set) var fresh: [String: LoadFailure] = [:]
    
    // A line for each failure new to this observation.
    private var announcements: [String] = []
    
    // What the daemon's reload writes on stderr for the failures new to this
    // observation, a line each, and nothing where none is new.
    var announcement: String {
        announcements.map { line in "forge: \(line)\n" }.joined()
    }
    
    // MARK: - Initializer
    init(prior: [String: LoadFailure]) {
        self.prior = prior
    }
    
    // MARK: - Public
    mutating func reuse(source: String, mtime: Date) -> Bool {
        guard let existing = prior[source], existing.mtime == mtime else { return false }
        
        fresh[source] = existing
        
        return true
    }
    
    // A failure is new where the observation before held none for the file,
    // or one with another reason or of another version of it.
    mutating func record(
        source: String,
        reason: String,
        mtime: Date,
        stderrLine: String,
        name: String? = nil
    ) {
        fresh[source] = LoadFailure(path: source, reason: reason, mtime: mtime, name: name)
        
        if let standing = prior[source], standing.reason == reason, standing.mtime == mtime { return }
        
        announcements.append(stderrLine)
    }
    
    // A collision new to this observation. Its failures stand beside the
    // ledger's, and the ledger holds its line.
    mutating func record(collision reason: String) {
        announcements.append(reason)
    }
    
    mutating func recordLegacyJSONSpecs(in directory: URL, kind: String) {
        let fileManager = FileManager.default
        
        for file in scanStoreFiles(in: directory, pathExtension: "json").files {
            guard let attributes = try? fileManager.attributesOfItem(atPath: file.url.path),
                let mtime = attributes[.modificationDate] as? Date
            else {
                continue
            }
            
            if reuse(source: file.source, mtime: mtime) { continue }
            
            let reason = "legacy JSON spec ignored — \(kind) files are *.\(specFileExtension); convert or remove"
            
            record(
                source: file.source,
                reason: reason,
                mtime: mtime,
                stderrLine: "\(reason) (\(file.source))"
            )
        }
    }
    
    // MARK: - Private
}
