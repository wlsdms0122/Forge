//
//  DiagnosticsTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import Forge

@Suite("Diagnostics Tests")
struct DiagnosticsTests {
    @Test("finding the last line skips trailing blank lines")
    func lastLineSkipsTrailingBlanks() {
        #expect(Diagnostics.lastLine("a\nb\n\n  \n") == "b")
    }
    
    @Test("the last line of empty input is an empty string")
    func lastLineEmpty() {
        #expect(Diagnostics.lastLine("\n  \n") == "")
    }
    
    @Test("with a single line, that line is the last line")
    func lastLineSingle() {
        #expect(Diagnostics.lastLine("  only line  ") == "only line")
    }
    
    @Test("CRLF is recognized as a line boundary")
    func handlesCRLF() {
        #expect(Diagnostics.lastLine("first\r\nlast\r\n") == "last")
    }
    
    @Test("the stdout tail is truncated to the cap")
    func stdoutTailCaps() {
        // Given
        let filler = String(repeating: "y", count: 800)

        // Then
        #expect(Diagnostics.stdoutTail(filler, limit: 500).count == 500)
    }
}
