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
    
    mutating func record(
        source: String,
        reason: String,
        mtime: Date,
        stderrLine: String,
        name: String? = nil
    ) {
        fresh[source] = LoadFailure(path: source, reason: reason, mtime: mtime, name: name)
        
        FileHandle.standardError.write(Data("forge: \(stderrLine)\n".utf8))
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
