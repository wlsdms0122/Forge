//
//  FireLedgerTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("FireLedger Tests")
struct FireLedgerTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("fireledger")

    // MARK: - Initializer
    // MARK: - Test
    @Test("Remaining entries survive when one timestamp is corrupt")
    func keepsValidEntriesWhenOneTimestampIsCorrupt() async throws {
        // Given
        let path = try temporary.file("fired.json")
        let raw = [
            "good": ISO8601.string(Date(timeIntervalSince1970: 1_700_000_000)),
            "bad": "not-a-timestamp",
        ]
        try JSONSerialization.data(withJSONObject: raw).write(to: path)

        // When
        let snapshot = await FireLedger(path: path).snapshot()

        // Then
        #expect(snapshot["good"] != nil, "a corrupt entry must not kill the rest")
        #expect(snapshot["bad"] == nil)
    }
}
