//
//  FolderGuardTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/24/26.
//

import Foundation
import Testing

@Suite("FolderGuard Tests")
struct FolderGuardTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("every folder is a group of folders or a module whose only folder is Model")
    func everyFolderIsAGroupOrAModule() throws {
        // Given
        let package = try PackageSource()
        let roots = [
            package.sources.appendingPathComponent("Forge"),
            package.sources.appendingPathComponent("ForgeCLI"),
            package.tests.appendingPathComponent("ForgeTests")
        ]
        var folders: [URL] = []

        for root in roots {
            folders += try Self.folders(under: root)
        }

        #expect(folders.count > 50, "if the folders cannot be read, this guard is meaningless, not passing")

        // When
        var offenders: [String] = []

        for folder in folders {
            let (hasFiles, subfolders) = try Self.contents(of: folder)
            let name = folder.lastPathComponent
            let allowed: Set<String>

            if roots.contains(folder) {
                allowed = subfolders

                if hasFiles {
                    offenders.append("\(Self.relative(folder, to: package.root)): files at the target root")
                }
            } else if name == "Model" {
                allowed = ["Extension"]
            } else if name == "Extension" {
                allowed = []

                if folder.deletingLastPathComponent().lastPathComponent != "Model" {
                    offenders.append("\(Self.relative(folder, to: package.root)): Extension outside Model")
                }
            } else {
                allowed = hasFiles ? ["Model"] : subfolders.subtracting(["Model"])
            }

            for subfolder in subfolders.subtracting(allowed).sorted() {
                offenders.append("\(Self.relative(folder, to: package.root)): files beside \(subfolder)/")
            }
        }

        // Then
        #expect(offenders == [], "a folder holds folders only, or files with a Model folder at most")
    }

    // MARK: - Public
    // MARK: - Private
    private static func folders(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            throw DirectoryNotEnumerable(directory: root)
        }

        var folders = [root]

        for case let url as URL in enumerator where try isFolder(url) {
            folders.append(url)
        }

        return folders
    }

    private static func contents(of folder: URL) throws -> (hasFiles: Bool, subfolders: Set<String>) {
        let entries = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        var hasFiles = false
        var subfolders: Set<String> = []

        for entry in entries {
            if try isFolder(entry) {
                subfolders.insert(entry.lastPathComponent)
            } else {
                hasFiles = true
            }
        }

        return (hasFiles, subfolders)
    }

    private static func isFolder(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
    }

    private static func relative(_ folder: URL, to root: URL) -> String {
        String(folder.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }
}
