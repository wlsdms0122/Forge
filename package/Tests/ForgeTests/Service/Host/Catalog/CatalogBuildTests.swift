//
//  CatalogBuildTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/22/26.
//

import Foundation
import Testing
import Warp
@testable import Forge

// Every workflow in the catalog directory `FORGE_CATALOG` is read and built
// the way the daemon's catalog reads and builds it at a reload: leaning on
// the library and on the other files, each built against the files that
// build. Nothing runs. Without the variable the suite asks nothing.
//
//   FORGE_CATALOG=<dir> swift test --filter CatalogBuildTests
//
// Each file prints one line: `<path>: ok`, or `<path>: <refusal>`, a build
// refusal starting `build:`. The files that built are then built whole, and
// the descriptions and hints the catalog hands back beside them are counted.
@Suite("Catalog build")
struct CatalogBuildTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("every workflow in the catalog loads and builds, and the catalog builds whole")
    func catalogBuilds() async throws {
        guard let path = ProcessInfo.processInfo.environment["FORGE_CATALOG"] else { return }

        let sut = try WorkflowCatalog(directory: URL(fileURLWithPath: path).standardizedFileURL)
        let catalog = await sut.catalog()

        for entry in catalog.entries {
            print("\(entry.source): ok")
        }

        for failure in catalog.failures {
            print("\(failure.path): \(failure.reason)")
        }

        _ = try await Builder().build(await sut.modules() + ForgeVocabulary.shipped.get().linkables)
        print("catalog: ok, \(catalog.entries.count) of \(catalog.entries.count + catalog.failures.count)")

        let descriptions = catalog.entries.filter { entry in entry.workflow.description != nil }.count
        let hints = catalog.entries.flatMap(\.workflow.contract.inputs).filter { input in input.hint != nil }.count

        print("prose: \(descriptions) descriptions, \(hints) hints")

        #expect(catalog.failures.isEmpty, "\(catalog.failures.count) refusal(s)")
    }

    // MARK: - Public
    // MARK: - Private
}
