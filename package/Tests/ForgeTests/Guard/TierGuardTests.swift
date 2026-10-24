//
//  TierGuardTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/24/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("TierGuard Tests")
struct TierGuardTests {
    // MARK: - Property
    private static let tiers = ["Core", "Error", "Module", "Service", "Feature"]
    private static let declaration = #"(?:struct|class|enum|protocol|actor|typealias)\s+([A-Z]\w*)"#

    // MARK: - Initializer
    // MARK: - Test
    @Test("a Core, Error or Module file names no type of a higher tier")
    func lowerTiersNameNoHigherTier() throws {
        // Given
        let package = try PackageSource()
        let root = package.sources.appendingPathComponent("Forge")
        let files = try package.swiftFiles(in: root)
        let topLevel = #"^(?:[@\w()]+\s+)*"# + Self.declaration
        var declared: [String: Int] = [:]

        for url in files {
            guard let tier = Self.tier(of: url, under: root) else { continue }

            for name in try Self.matches(topLevel, in: try Self.code(of: url)) {
                declared[name] = tier
            }
        }

        #expect(declared.values.contains(4), "if no Feature type was read, this guard is meaningless, not passing")

        // When
        var offenders: [String] = []

        for url in files {
            guard let tier = Self.tier(of: url, under: root), tier <= 2 else { continue }

            let code = try Self.code(of: url)
            let own = Set(try Self.matches(Self.declaration, in: code))
            let named = Set(try Self.matches(#"\b([A-Z]\w*)\b"#, in: code))

            for name in named.subtracting(own).sorted() where (declared[name] ?? 0) > tier {
                offenders.append("\(url.lastPathComponent): \(name)")
            }
        }

        // Then
        #expect(offenders == [], "Core, Error and Module name only their own tier and the tiers below")
    }

    // MARK: - Public
    // MARK: - Private
    private static func tier(of url: URL, under root: URL) -> Int? {
        let relative = url.path.dropFirst(root.path.count + 1)

        return tiers.firstIndex { tier in relative.hasPrefix(tier + "/") }
    }

    // The file's text without comments and string literals.
    private static func code(of url: URL) throws -> String {
        var text = try String(contentsOf: url, encoding: .utf8)

        for pattern in [#"/\*[\s\S]*?\*/"#, #"//[^\n]*"#, #""""[\s\S]*?""""#, #""(?:\\.|[^"\\\n])*""#] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        return text
    }

    private static func matches(_ pattern: String, in text: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
        let source = text as NSString

        return expression
            .matches(in: text, range: NSRange(location: 0, length: source.length))
            .map { match in source.substring(with: match.range(at: 1)) }
    }
}
