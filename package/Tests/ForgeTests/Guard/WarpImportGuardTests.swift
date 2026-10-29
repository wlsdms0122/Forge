//
//  WarpImportGuardTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/24/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("WarpImportGuard Tests")
struct WarpImportGuardTests {
    // MARK: - Property
    private static let reader = "Forge/Service/Host/"

    // MARK: - Initializer
    // MARK: - Test
    @Test("only the host imports Warp or its front end")
    func warpIsImportedOnlyByTheHost() throws {
        // Given
        let package = try PackageSource()
        let root = package.sources
        let files = try package.swiftFiles(in: root)
        let importing = try NSRegularExpression(pattern: #"^\s*(?:@\w+\s+)*import\s+(?:(?:struct|class|enum|protocol|typealias|func|let|var)\s+)?Warp\w*\b"#, options: .anchorsMatchLines)
        var readerFound = false

        // When
        var offenders: [String] = []

        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)

            guard importing.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil else {
                continue
            }

            let relative = String(url.path.dropFirst(root.path.count + 1))

            if relative.hasPrefix(Self.reader) {
                readerFound = true
            } else {
                offenders.append(relative)
            }
        }

        // Then
        #expect(readerFound, "if no host file imports Warp, this guard is meaningless, not passing")
        #expect(offenders == [], "Warp is the host's: no file outside Service/Host imports it")
    }

    // MARK: - Public
    // MARK: - Private
}
