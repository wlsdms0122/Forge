//
//  StoreScan.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

let specFileExtension = "yaml"

struct StoreScan {
    struct Obstruction {
        // MARK: - Property
        let scope: String
        let reason: String
        
        var description: String { scope.isEmpty ? reason : "\(scope): \(reason)" }
        
        // MARK: - Initializer
        // MARK: - Public
        func covers(source: String) -> Bool {
            scope.isEmpty || source == scope || source.hasPrefix(scope + "/")
        }
        
        // The obstruction as a store's list reports it.
        func failure(kind: String) -> LoadFailure {
            LoadFailure(
                path: "<scan>",
                reason: "\(kind) directory scan incomplete — \(description)",
                mtime: .distantPast
            )
        }
        
        // MARK: - Private
    }
    
    // MARK: - Property
    let files: [ScannedFile]
    
    var obstructions: [Obstruction]
    
    var isComplete: Bool { obstructions.isEmpty }
    
    // MARK: - Initializer
    init(files: [ScannedFile], obstructions: [Obstruction] = []) {
        self.files = files
        self.obstructions = obstructions
    }
    
    // The files under a directory with this extension, and what the
    // enumeration could not see.
    init(directory: URL, pathExtension: String) {
        let base = directory.standardizedFileURL.path
        
        func relative(_ url: URL) -> String? {
            let full = url.standardizedFileURL.path
            
            guard full.hasPrefix(base + "/") else { return nil }
            
            return String(full.dropFirst(base.count + 1))
        }
        
        var obstructions: [Obstruction] = []
        
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, error in
                    obstructions.append(.init(scope: relative(url) ?? "", reason: "\(error)"))
                    
                    return true
                }
            )
        else {
            self.init(
                files: [],
                obstructions: [
                    .init(
                        scope: "",
                        reason: "directory could not be enumerated (\(directory.path))"
                    )
                ]
            )
            
            return
        }
        
        var files: [ScannedFile] = []
        
        for case let url as URL in enumerator where url.pathExtension == pathExtension {
            files.append(ScannedFile(url: url, source: relative(url) ?? url.lastPathComponent))
        }
        
        self.init(files: files, obstructions: obstructions)
    }
    
    // MARK: - Public
    func isUnobserved(source: String) -> Bool {
        obstructions.contains { obstruction in obstruction.covers(source: source) }
    }
    
    // Each file with when it last changed. A file whose metadata cannot be
    // read obstructs the scan at that file.
    mutating func observe() -> [ObservedFile] {
        var observed: [ObservedFile] = []
        
        for file in files {
            guard
                let attributes = try? FileManager.default.attributesOfItem(atPath: file.url.path),
                let mtime = attributes[.modificationDate] as? Date
            else {
                obstructions.append(
                    .init(
                        scope: file.source,
                        reason: "file metadata could not be read"
                            + " — existence observed, content unknown"
                    )
                )
                
                continue
            }
            
            observed.append(ObservedFile(file: file, mtime: mtime))
        }
        
        return observed
    }
    
    // MARK: - Private
}

func isStoreSafeID(_ id: String) -> Bool {
    !id.isEmpty && !id.hasPrefix(".") && id.allSatisfy { character in
        character.isLetter
            || character.isNumber
            || character == "."
            || character == "_"
            || character == "-"
    }
}
