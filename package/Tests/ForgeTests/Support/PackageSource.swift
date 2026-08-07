//
//  PackageSource.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

/// The package layout used by guards that read the sources to check invariants.
///
/// Calling `deletingLastPathComponent()` a fixed number of times from `#filePath` means
/// that the moment a file moves to a different depth, it **reads the wrong path yet passes
/// as "no violations"**. That failure mode is worse because it is silent — so instead of
/// counting depth, walk upward until `Package.swift` is found, and throw rather than
/// quietly returning an empty result when it isn't.
struct PackageSource {
    // MARK: - Property
    let root: URL

    // MARK: - Initializer
    init(from filePath: String = #filePath) throws {
        var candidate = URL(fileURLWithPath: filePath).deletingLastPathComponent()

        while candidate.path != "/" {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("Package.swift").path
            ) {
                root = candidate

                return
            }

            candidate = candidate.deletingLastPathComponent()
        }

        throw PackageRootNotFound(startedAt: filePath)
    }

    // MARK: - Public
    var sources: URL {
        root.appendingPathComponent("Sources")
    }

    var tests: URL {
        root.appendingPathComponent("Tests")
    }

    /// All Swift files under `directory`. Recursive and path-sorted, so the order is the same on every run.
    func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            throw DirectoryNotEnumerable(directory: directory)
        }

        return enumerator
            .compactMap { element in element as? URL }
            .filter { url in url.pathExtension == "swift" }
            .sorted { lhs, rhs in lhs.path < rhs.path }
    }

    // MARK: - Private
}
