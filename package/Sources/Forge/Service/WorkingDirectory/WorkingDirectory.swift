//
//  WorkingDirectory.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// Where a daemon resolves the paths it is handed. An absolute path names its
// file as written; a relative one names the file under the directory.
actor WorkingDirectory {
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
    // The file this path names, or nil where no file is there, a directory
    // among them.
    func file(at path: String) throws -> URL? {
        let url = try url(of: path)

        return isFile(url) ? url : nil
    }

    func resolve(_ path: String) throws -> URL {
        guard let url = try file(at: path) else {
            throw ResourceError("resource not found: \(path)")
        }

        return url
    }

    func read(_ path: String) throws -> String {
        try text(of: resolve(path), at: path)
    }

    // A file the directory hands out as its own: named relative to it, no
    // hidden part, and not led out of it by a link.
    func readInside(_ path: String) throws -> String {
        guard let url = try fileInside(at: path) else {
            throw ResourceError("resource not found: \(path)")
        }

        return try text(of: url, at: path)
    }

    // Every file `readInside` reads.
    func all() -> [Entry] {
        guard
            let base = directory,
            let enumerator = FileManager.default.enumerator(
                at: base,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsPackageDescendants]
            )
        else {
            return []
        }

        let basePath = base.path
        var entries: [Entry] = []

        for case let url as URL in enumerator {
            let full = url.standardizedFileURL.path

            guard full.hasPrefix(basePath + "/") else { continue }

            let relativePath = String(full.dropFirst(basePath.count + 1))

            guard
                let file = try? fileInside(at: relativePath),
                let values = try? file.resolvingSymlinksInPath().resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey]
                )
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
    // A policy matches a workflow by the prefix of its path as written, so a
    // path never steps back or in place: `bot/../brain/x.yaml` would pass a
    // grant on `bot/*`.
    private func url(of path: String) throws -> URL {
        let absolute = path.hasPrefix("/")
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst(absolute ? 1 : 0)

        guard parts.allSatisfy({ part in !part.isEmpty && part != "." && part != ".." }) else {
            throw ResourceError("path '\(path)' has an empty, '.' or '..' part; a policy matches the path as written")
        }

        if absolute { return URL(fileURLWithPath: path) }

        guard let directory else {
            throw ResourceError("relative path '\(path)' given but working_directory not configured")
        }

        return directory.appendingPathComponent(path)
    }

    private func fileInside(at path: String) throws -> URL? {
        guard !path.hasPrefix("/") else {
            throw ResourceError("resource path '\(path)' is absolute; a resource is named under the working directory")
        }

        let url = try url(of: path)

        guard !path.split(separator: "/").contains(where: { part in part.hasPrefix(".") }) else {
            throw ResourceError("resource path '\(path)' has a hidden component; hidden files are not resources")
        }

        guard isFile(url), let directory else { return nil }

        let realBase = directory.resolvingSymlinksInPath().path

        guard url.resolvingSymlinksInPath().path.hasPrefix(realBase + "/") else {
            throw ResourceError("resource path '\(path)' resolves outside the working directory via symlink")
        }

        return url
    }

    private func isFile(_ url: URL) -> Bool {
        let values = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey])

        return values?.isRegularFile == true
    }

    private func text(of url: URL, at path: String) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ResourceError("resource read failed (\(path)): \(error)")
        }
    }
}
