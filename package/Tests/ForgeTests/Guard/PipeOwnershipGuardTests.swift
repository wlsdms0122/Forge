//
//  PipeOwnershipGuardTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

/// A guard that reads the source to check an invariant — it inspects the codebase's *shape*, not the subject's *behavior*.
@Suite("PipeOwnershipGuard Tests")
struct PipeOwnershipGuardTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("the child's stdout/stderr attach only through PipeReader-owned handles")
    func childOutputIsAttachedOnlyThroughPipeReader() throws {
        // Given
        let source = try Self.subprocessSource()
        let assignment = try NSRegularExpression(
            pattern: #"process\.(standardOutput|standardError)\s*=\s*(\S+)"#)

        // When
        let text = source as String
        var attachments: [String] = []
        assignment.enumerateMatches(
            in: text,
            range: NSRange(location: 0, length: source.length)
        ) { match, _, _ in
            guard let match else { return }

            attachments.append(source.substring(with: match.range(at: 2)))
        }

        // Then
        #expect(attachments.count == 2, "if the child output wiring cannot be found, this guard is meaningless, not passing")
        #expect(
            attachments.allSatisfy { target in target.hasSuffix("Reader.writingHandle") },
            "child output must go only through PipeReader-owned write ends — actual wiring: \(attachments)")
    }

    @Test("no path lets anyone else read the read end or flip its flags")
    func nobodyElseReadsOrReconfiguresTheReadEnd() throws {
        // Given
        let source = try Self.subprocessSource()

        // The tools from the era when two owners touched the read fd: readabilityHandler
        // runs on its own queue, and F_SETFL swaps that fd's flags — the moment they
        // overlap, availableData throws EAGAIN as an ObjC exception and the process aborts.
        let forbidden = [
            "readabilityHandler",
            "availableData",
            "readDataToEndOfFile",
            "F_SETFL",
            "DispatchSource.makeReadSource"
        ]

        // When
        let offenders = forbidden.filter { token in source.contains(token) }

        // Then
        #expect(offenders == [], "the read end must have PipeReader as its sole owner")
    }

    // MARK: - Private
    /// The single home of the child output wiring. Throws instead of staying silent when unreadable.
    private static func subprocessSource() throws -> NSString {
        let package = try PackageSource()
        let url = package.sources
            .appendingPathComponent("Forge/Module/Process/Subprocess.swift")
        let text = try String(contentsOf: url, encoding: .utf8)

        #expect(text.count > 1000, "if Subprocess.swift cannot be read, this guard is meaningless, not passing")

        return text as NSString
    }
}
