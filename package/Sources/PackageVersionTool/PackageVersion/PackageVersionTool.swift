//
//  PackageVersionTool.swift
//  PackageVersionTool
//
//  Created by JSilver on 11/1/26.
//

import Foundation
import TOMLKit

// Writes `packageVersion` from the `[package] version` of an open-package
// manifest.
@main
struct PackageVersionTool {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())

        guard arguments.count == 2 else {
            fail("usage: PackageVersionTool <manifest.toml> <PackageVersion.swift>")
        }

        let manifest = URL(filePath: arguments[0])
        let output = URL(filePath: arguments[1])

        do {
            let version = try version(of: manifest)

            try """
            let packageVersion = "\(version)"

            """.write(to: output, atomically: true, encoding: .utf8)
        } catch {
            fail("\(manifest.path): \(error)")
        }
    }

    // MARK: - Private
    // Only the canonical `major.minor.patch` is taken, so the binary reports
    // the very string its manifest holds.
    private static func version(of manifest: URL) throws -> String {
        let table = try TOMLTable(string: String(contentsOf: manifest, encoding: .utf8))

        guard let version = table["package"]?.table?["version"]?.string else {
            throw PackageVersionToolError.undeclaredVersion
        }

        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        let canonical = parts.count == 3 && parts.allSatisfy { part in
            !part.isEmpty
                && part.allSatisfy(\.isASCII)
                && part.allSatisfy(\.isNumber)
                && (part == "0" || !part.hasPrefix("0"))
        }

        guard canonical else {
            throw PackageVersionToolError.unreadableVersion(version)
        }

        return version
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(1)
    }
}
