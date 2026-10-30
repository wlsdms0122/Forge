//
//  LoadFailureLedgerTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/24/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("LoadFailureLedger Tests")
struct LoadFailureLedgerTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("A ledger records each failure and holds a line for each one new to the observation")
    func aLedgerHoldsTheLinesOfNewFailures() {
        // Given
        let stamp = Date(timeIntervalSinceReferenceDate: 0)
        let standing = LoadFailure(path: "kept.yaml", reason: "broken", mtime: stamp)
        var sut = LoadFailureLedger(prior: ["kept.yaml": standing])

        // When
        sut.record(source: "kept.yaml", reason: "broken", mtime: stamp, stderrLine: "kept failed")
        sut.record(source: "new.yaml", reason: "broken", mtime: stamp, stderrLine: "new failed")
        sut.record(collision: "workflow name 'a' collides across: a.yaml, b/a.yaml")

        // Then
        #expect(sut.fresh.keys.sorted() == ["kept.yaml", "new.yaml"])
        #expect(sut.announcement == "forge: new failed\nforge: workflow name 'a' collides across: a.yaml, b/a.yaml\n")
    }

    @Test("A ledger with nothing new announces nothing")
    func aLedgerWithNothingNewAnnouncesNothing() {
        // Given
        let stamp = Date(timeIntervalSinceReferenceDate: 0)
        var sut = LoadFailureLedger(
            prior: ["kept.yaml": LoadFailure(path: "kept.yaml", reason: "broken", mtime: stamp)]
        )

        // When
        sut.record(source: "kept.yaml", reason: "broken", mtime: stamp, stderrLine: "kept failed")

        // Then
        #expect(sut.announcement.isEmpty)
    }

    // MARK: - Public
    // MARK: - Private
}
