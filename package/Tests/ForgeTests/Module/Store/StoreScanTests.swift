//
//  StoreScanTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/25/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("StoreScan Tests")
struct StoreScanTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("A file whose metadata cannot be read obstructs the scan at that file")
    func unreadableMetadataIsAnObstruction() {
        // Given
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("storescan-\(UUID().uuidString)")
            .appendingPathComponent("gone.yaml")
        var sut = StoreScan(files: [ScannedFile(url: missing, source: "gone.yaml")])

        // When
        let observed = sut.observe()

        // Then
        #expect(observed.isEmpty)
        #expect(sut.obstructions.map(\.scope) == ["gone.yaml"])
        #expect(sut.isUnobserved(source: "gone.yaml"))
        #expect(!sut.isUnobserved(source: "other.yaml"))
    }

    // MARK: - Public
    // MARK: - Private
}
