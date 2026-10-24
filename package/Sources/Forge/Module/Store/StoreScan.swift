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
    
    // MARK: - Public
    func isUnobserved(source: String) -> Bool {
        obstructions.contains { obstruction in obstruction.covers(source: source) }
    }
    
    // MARK: - Private
}

func scanStoreFiles(in directory: URL, pathExtension: String) -> StoreScan {
    let fileManager = FileManager.default
    let base = directory.standardizedFileURL.path
    
    func relative(_ url: URL) -> String? {
        let full = url.standardizedFileURL.path
        
        guard full.hasPrefix(base + "/") else { return nil }
        
        return String(full.dropFirst(base.count + 1))
    }
    
    var obstructions: [StoreScan.Obstruction] = []
    
    guard
        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                obstructions.append(.init(scope: relative(url) ?? "", reason: "\(error)"))
                
                return true
            }
        )
    else {
        return StoreScan(
            files: [],
            obstructions: [
                .init(
                    scope: "",
                    reason: "directory could not be enumerated (\(directory.path))"
                )
            ]
        )
    }
    
    var files: [ScannedFile] = []
    
    for case let url as URL in enumerator where url.pathExtension == pathExtension {
        files.append(ScannedFile(url: url, source: relative(url) ?? url.lastPathComponent))
    }
    
    return StoreScan(files: files, obstructions: obstructions)
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
