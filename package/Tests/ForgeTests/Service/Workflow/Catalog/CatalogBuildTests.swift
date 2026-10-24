//
//  CatalogBuildTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/22/26.
//

import Foundation
import Testing
import Warp
import WarpSyntax
@testable import Forge

// Every workflow in the catalog directory `FORGE_CATALOG` loads through the
// front end, and the catalog builds against the Forge module and the standard
// vocabulary. Nothing runs. Without the variable the suite asks nothing.
//
//   FORGE_CATALOG=<dir> swift test --filter CatalogBuildTests
//
// Each file prints one line: `<path>: ok`, or `<path>: load: <refusal>` or
// `<path>: build: <refusal>`. A file is built with the siblings that build
// alone, so a refusal is reported for the file that holds it and one broken
// file does not hide another's, and the catalog is then built whole.
@Suite("Catalog build")
struct CatalogBuildTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("every workflow in the catalog loads and the catalog builds")
    func catalogBuilds() async throws {
        guard let path = ProcessInfo.processInfo.environment["FORGE_CATALOG"] else { return }

        let directory = URL(fileURLWithPath: path).standardizedFileURL
        let frontend = ForgeSpec.frontend()
        let linkables = try ForgeSpec.linkables()
        var loaded: [(path: String, module: Warp.Module)] = []
        var refused: [String] = []

        for file in files(in: directory) {
            let relative = String(file.path.dropFirst(directory.path.count + 1))

            do {
                let document = try frontend.document(from: try Data(contentsOf: file))

                loaded.append((relative, try Loader().load(document, identity: try Identity.of(document))))
            } catch {
                refused.append("\(relative): load: \(error)")
            }
        }

        var standing: [Int] = []

        for (index, entry) in loaded.enumerated() {
            if (try? await Builder().build([entry.module] + linkables)) != nil {
                standing.append(index)
            }
        }

        for (index, entry) in loaded.enumerated() {
            let siblings = standing
                .filter { other in other != index }
                .map { other in loaded[other].module }

            do {
                _ = try await Builder().build([entry.module] + siblings + linkables)
                print("\(entry.path): ok")
            } catch {
                refused.append("\(entry.path): build: \(error)")
            }
        }

        for line in refused {
            print(line)
        }

        do {
            _ = try await Builder().build(loaded.map(\.module) + linkables)
            print("catalog: ok")
        } catch {
            print("catalog: build: \(error)")
            refused.append("catalog: build: \(error)")
        }

        #expect(refused.isEmpty, "\(refused.count) refusal(s)")
    }

    // MARK: - Public
    // MARK: - Private
    private func files(in directory: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        let found = (enumerator?.allObjects as? [URL]) ?? []

        return found
            .filter { url in url.pathExtension == "yaml" }
            .map(\.standardizedFileURL)
            .sorted { one, other in one.path < other.path }
    }
}
