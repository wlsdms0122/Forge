//
//  TemporaryDirectory.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

/// Temporary space for a single test. Held as a suite property, it opens fresh per test and is deleted when done.
///
///     @Suite("JobStore Tests")
///     struct JobStoreTests {
///         private let temporary = TemporaryDirectory("jobstore")
///
///         @Test func loadsSeededJobs() throws {
///             let directory = try temporary.make("seed")
///             ...
///         }
///     }
///
/// Leaving cleanup to `defer` gets skipped on early returns and failure paths, and nobody
/// ever looks at the directories left behind. Tying the lifetime to the type removes that
/// branch. All sub-spaces go under this root, so deleting the one root is enough.
final class TemporaryDirectory: Sendable {
    // MARK: - Property
    let url: URL

    // MARK: - Initializer
    init(_ name: String) {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-\(name)-\(UUID().uuidString.prefix(6))")
            .standardizedFileURL
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Public
    /// A directory inside this space. With no `label`, it is the root itself.
    ///
    /// The returned URL is explicitly a directory (`isDirectory: true`). `appendingPathComponent`
    /// only judges a path to be a directory — and appends the trailing slash — **when the path
    /// already exists**, and if a slash-less URL is given as the base of
    /// `URL(fileURLWithPath:relativeTo:)`, the last component is treated as a file name and
    /// silently resolves against the parent. Directory-ness is not left to creation order.
    @discardableResult
    func make(_ label: String? = nil) throws -> URL {
        let directory = label.map { label in url.appendingPathComponent(label) } ?? url
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return URL(fileURLWithPath: directory.path, isDirectory: true)
    }

    /// A file path inside this space. Does not create the file, only guarantees the containing directory.
    func file(_ name: String) throws -> URL {
        try make().appendingPathComponent(name, isDirectory: false)
    }

    @discardableResult
    func write(_ contents: String, to name: String) throws -> URL {
        let destination = try file(name)
        try contents.write(to: destination, atomically: true, encoding: .utf8)

        return destination
    }

    // MARK: - Private
}
