//
//  ResourceStore.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

actor ResourceStore {
    struct Entry: Sendable {
        // MARK: - Property
        let path: String
        let size: Int
        let mtime: Date
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    let directory: URL?
    
    // MARK: - Initializer
    init(directory: URL?) {
        self.directory = directory?.standardizedFileURL
    }
    
    // MARK: - Public
    func resolve(_ relativePath: String) throws -> URL {
        guard let base = directory else {
            throw ProtocolError(
                "resource '@\(relativePath)' requested but resource_directory not configured"
            )
        }
        
        return try admit(relativePath, base: base)
    }
    
    func read(_ relativePath: String) throws -> String {
        let url = try resolve(relativePath)
        
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ProtocolError("resource read failed (\(relativePath)): \(error)")
        }
    }
    
    func all() -> [Entry] {
        guard
            let base = directory,
            FileManager.default.fileExists(atPath: base.path)
        else {
            return []
        }
        
        guard
            let enumerator = FileManager.default.enumerator(
                at: base,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ],
                options: [.skipsPackageDescendants]
            )
        else {
            return []
        }
        
        let basePath = base.path
        var entries: [Entry] = []
        
        for case let url as URL in enumerator {
            let standardized = url.standardizedFileURL
            let full = standardized.path
            
            guard full.hasPrefix(basePath + "/") else { continue }
            
            let relativePath = String(full.dropFirst(basePath.count + 1))
            
            guard (try? admit(relativePath, base: base)) != nil else { continue }
            
            let real = standardized.resolvingSymlinksInPath()
            
            guard
                let values = try? real.resourceValues(
                    forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
                ),
                values.isRegularFile == true
            else {
                continue
            }
            
            entries.append(
                Entry(
                    path: relativePath,
                    size: values.fileSize ?? 0,
                    mtime: values.contentModificationDate ?? .distantPast
                )
            )
        }
        
        entries.sort { left, right in left.path < right.path }
        
        return entries
    }
    
    // MARK: - Private
    private func admit(_ relativePath: String, base: URL) throws -> URL {
        guard
            !relativePath.split(separator: "/").contains(where: { component in
                component.hasPrefix(".") && component != "." && component != ".."
            })
        else {
            throw ProtocolError(
                "resource path '\(relativePath)' has a hidden component"
                    + " — hidden files are not resources"
            )
        }
        
        let target = URL(fileURLWithPath: relativePath, relativeTo: base).standardizedFileURL
        let basePath = base.path
        
        guard target.path == basePath || target.path.hasPrefix(basePath + "/") else {
            throw ProtocolError("resource path '\(relativePath)' escapes resource_directory")
        }
        
        guard FileManager.default.fileExists(atPath: target.path) else {
            throw ProtocolError("resource not found: \(relativePath)")
        }
        
        let real = target.resolvingSymlinksInPath()
        let realBase = base.resolvingSymlinksInPath()
        let realBasePath = realBase.path
        
        guard real.path == realBasePath || real.path.hasPrefix(realBasePath + "/") else {
            throw ProtocolError(
                "resource path '\(relativePath)' resolves outside resource_directory via symlink"
            )
        }
        
        return target
    }
}
