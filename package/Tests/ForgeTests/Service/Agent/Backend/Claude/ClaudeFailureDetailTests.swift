//
//  ClaudeFailureDetailTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import Forge

@Suite("ClaudeFailureDetail Tests")
struct ClaudeFailureDetailTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("failure detail looks at stderr first")
    func stderrTakesPriority() {
        // Given
        let detail = ClaudeBackend.failureDetail(stderr: "  boom: bad flag\n", stdout: "ignored")

        // Then
        #expect(detail == "boom: bad flag")
    }
    
    @Test("falls back to the stream JSON result when stderr is empty")
    func fallsBackToStreamJsonResult() {
        // Given
        let stdout = """
        {"type":"system","subtype":"init","session_id":"x"}
        {"type":"system","subtype":"api_retry","attempt":10,"error_status":529}
        {"type":"result","subtype":"success","is_error":true,"api_error_status":529,"result":"API Error: 529 Overloaded. This is a server-side issue, usually temporary."}
        """
        let detail = ClaudeBackend.failureDetail(stderr: "", stdout: stdout)

        // Then
        #expect(detail == "API Error: 529 Overloaded. This is a server-side issue, usually temporary.")
    }
    
    @Test("when both are empty, the detail stays empty — nothing is invented")
    func bothEmpty() {
        #expect(ClaudeBackend.failureDetail(stderr: "  \n", stdout: "") == "")
    }
    
    @Test("otherwise uses the stdout tail")
    func plainStdoutTail() {
        // Given
        let detail = ClaudeBackend.failureDetail(stderr: "", stdout: "starting\nfatal: something broke\n\n")

        // Then
        #expect(detail == "fatal: something broke")
    }
    
    @Test("the detail is capped at the limit")
    func capped() {
        // Given
        let long = String(repeating: "x", count: 500)
        let detail = ClaudeBackend.failureDetail(stderr: long, stdout: "")

        // Then
        #expect(detail.count == 300)
    }
    
    // MARK: - Private
}
