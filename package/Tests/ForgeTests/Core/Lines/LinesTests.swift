//
//  LinesTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import Forge

@Suite("Lines Tests")
struct LinesTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("CRLF counts as a line boundary, and empty lines are preserved")
    func splitPreservesEmptyAndHandlesCRLF() {
        // Given
        let text = "a\r\nb\n\nc"

        // When
        let lines = Lines.split(text).map(String.init)

        // Then
        #expect(lines == ["a", "b", "", "c"])
    }

    @Test("nonEmpty trims CRLF and drops blank lines")
    func nonEmptyDropsBlankLines() {
        // Given
        let text = "a\r\nb\r\n"

        // When
        let lines = Lines.nonEmpty(text).map(String.init)

        // Then
        #expect(lines == ["a", "b"])
    }
}
