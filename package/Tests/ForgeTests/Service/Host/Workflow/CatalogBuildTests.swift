//
//  CatalogBuildTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/22/26.
//

import Foundation
import Testing
@testable import Forge

// Every workflow in the catalog directory `FORGE_CATALOG` is read and built
// the way the daemon's catalog reads and builds it at a reload: each file
// alone, leaning on the library, held to the entry convention and built into
// its own image. Nothing runs. Without the variable the suite asks nothing.
//
//   FORGE_CATALOG=<dir> swift test --filter CatalogBuildTests
//
// Each file prints one line: `<path>: ok`, or `<path>: <refusal>`, a build
// refusal starting `build:`. The descriptions and hints the catalog hands
// back beside the files that built are then counted.
@Suite("Catalog build")
struct CatalogBuildTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("every workflow in the catalog loads and builds on its own")
    func catalogBuilds() async throws {
        guard let path = ProcessInfo.processInfo.environment["FORGE_CATALOG"] else { return }

        let sut = try WorkflowCatalog(directory: URL(fileURLWithPath: path).standardizedFileURL)
        let snapshot = await sut.reload()

        for entry in snapshot.entries {
            print("\(entry.path): ok")
        }

        for failure in snapshot.failures {
            print("\(failure.path): \(failure.reason)")
        }

        print("catalog: ok, \(snapshot.entries.count) of \(snapshot.entries.count + snapshot.failures.count)")

        let descriptions = snapshot.entries.filter { entry in entry.description != nil }.count
        let hints = snapshot.entries.flatMap(\.contract.inputs).filter { input in input.hint != nil }.count

        print("prose: \(descriptions) descriptions, \(hints) hints")

        #expect(snapshot.failures.isEmpty, "\(snapshot.failures.count) refusal(s)")
    }

    // MARK: - Public
    // MARK: - Private
}
