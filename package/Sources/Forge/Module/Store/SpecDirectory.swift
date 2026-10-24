//
//  SpecDirectory.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// A directory of spec files, read again at each reload. A file whose
// modification time is unchanged keeps what it decoded to, or the failure
// the ledger holds for it; any other file is read and decoded by the store,
// and a refusal is recorded in the ledger. A directory that does not exist
// holds no file and hides none.
struct SpecDirectory<Value> {
    struct Loaded {
        // MARK: - Property
        let file: ObservedFile
        let value: Value
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct Reading {
        // MARK: - Property
        // Every file whose metadata was read, decoded or not.
        let observed: [ObservedFile]
        let loaded: [Loaded]
        // What the scan could not see, a file whose metadata could not be
        // read among them.
        let obstructions: [StoreScan.Obstruction]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    let directory: URL
    let pathExtension: String
    
    // The word a refusal's announcement names the store by.
    let kind: String
    
    private var decoded: [URL: Loaded] = [:]
    
    // MARK: - Initializer
    init(directory: URL, pathExtension: String = specFileExtension, kind: String) {
        self.directory = directory
        self.pathExtension = pathExtension
        self.kind = kind
    }
    
    // MARK: - Public
    // The files under the directory, those under `nested` left out.
    mutating func read(
        skipping nested: URL? = nil,
        recording ledger: inout LoadFailureLedger,
        decode: (ObservedFile, Data) throws -> Value
    ) -> Reading {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            decoded = [:]
            
            return Reading(observed: [], loaded: [], obstructions: [])
        }
        
        let nestedPath = nested?.standardizedFileURL.path
        let found = StoreScan(directory: directory, pathExtension: pathExtension)
        let files = found.files.filter { file in
            guard let nestedPath else { return true }
            
            return !file.url.standardizedFileURL.path.hasPrefix(nestedPath + "/")
        }
        var scan = StoreScan(files: files, obstructions: found.obstructions)
        let observed = scan.observe()
        var fresh: [URL: Loaded] = [:]
        
        for file in observed {
            let url = file.file.url
            
            if let existing = decoded[url], existing.file.mtime == file.mtime {
                fresh[url] = existing
                
                continue
            }
            
            if ledger.reuse(source: file.file.source, mtime: file.mtime) { continue }
            
            do {
                fresh[url] = Loaded(file: file, value: try decode(file, try Data(contentsOf: url)))
            } catch let refusal as LoadRefusal {
                ledger.record(
                    source: file.file.source,
                    reason: refusal.message,
                    mtime: file.mtime,
                    stderrLine: refusal.line
                )
            } catch {
                ledger.record(
                    source: file.file.source,
                    reason: "\(error)",
                    mtime: file.mtime,
                    stderrLine: "\(kind) load failed (\(file.file.source)): \(error)"
                )
            }
        }
        
        decoded = fresh
        
        return Reading(
            observed: observed,
            loaded: observed.compactMap { file in fresh[file.file.url] },
            obstructions: scan.obstructions
        )
    }
    
    // MARK: - Private
}
