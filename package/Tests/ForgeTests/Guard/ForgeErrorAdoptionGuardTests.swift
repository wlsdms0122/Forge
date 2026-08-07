//
//  ForgeErrorAdoptionGuardTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

/// A guard that reads the sources and checks an invariant. It inspects the *shape* of the codebase, not the *behavior* of the target.
@Suite("ForgeErrorAdoptionGuard Tests")
struct ForgeErrorAdoptionGuardTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("every error type adopts the ForgeError family — bare Error escapes the fallback classification")
    func everyDeclaredErrorTypeAdoptsForgeError() throws {
        // Given
        let package = try PackageSource()
        let files = try package.swiftFiles(in: package.sources)
        #expect(files.count > 30, "if no sources could be read, this guard is meaningless rather than passing")
        let declaration = try NSRegularExpression(
            pattern: #"(?:struct|enum|final class|class)\s+(\w+)\s*:\s*([^\{\n]*)"#)

        // When
        var offenders: [String] = []

        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            let source = text as NSString
            declaration.enumerateMatches(
                in: text,
                range: NSRange(location: 0, length: source.length)
            ) { match, _, _ in
                guard let match else { return }

                let name = source.substring(with: match.range(at: 1))
                let conformance = source.substring(with: match.range(at: 2))
                let tokens = conformance
                    .split(separator: ",")
                    .map { token in token.trimmingCharacters(in: .whitespaces) }

                guard tokens.contains("Error") || tokens.contains("Swift.Error") else { return }
                guard !tokens.contains(where: { token in
                    token.hasSuffix("ForgeError") || token.hasSuffix("BackendError")
                }) else { return }

                offenders.append(
                    "\(url.lastPathComponent): \(name) [\(conformance.trimmingCharacters(in: .whitespaces))]")
            }
        }

        // Then
        #expect(offenders == [], "bare Error declarations — adopt ForgeError to enforce the fallbackAbsorbable classification")
    }
}
