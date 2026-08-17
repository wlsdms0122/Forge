//
//  ResultTextTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import ForgeCLI

@Suite("ResultText Tests")
struct ResultTextTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("a workflow result shows the declared outputs")
    func workflowResultShowsOutputs() {
        // Given
        let dict: [String: Any] = [
            "workflow_id": "wf-A4057576",
            "name": "<inline>",
            "status": "ok",
            "duration_ms": 9,
            "outputs": ["result": "hello from jineun-bot test\n"],
        ]
        let output = renderResultPlain(dict)

        // Then
        #expect(output.contains("status: ok"), Comment(rawValue: output))
        #expect(output.contains("outputs:"), Comment(rawValue: output))
        #expect(output.contains("result: hello from jineun-bot test"), "outputs content must be visible:\n\(output)")
        #expect(output.contains("wf-A4057576"), Comment(rawValue: output))
        #expect(!output.contains("test\n\n"), Comment(rawValue: output))
    }
    
    @Test("status comes on the first line — success or failure is readable without scrolling")
    func statusIsFirstLine() {
        // Given
        let dict: [String: Any] = ["duration_ms": 5, "status": "ok", "name": "x"]
        let first = renderResultPlain(dict).split(separator: "\n").first.map(String.init) ?? ""

        // Then
        #expect(first == "status: ok")
    }
    
    @Test("a failure shows the error details alongside")
    func failedResultShowsError() {
        // Given
        let dict: [String: Any] = [
            "status": "failed",
            "workflow_id": "wf-x",
            "error": ["type": "ShellError", "message": "exit 1"],
        ]
        let output = renderResultPlain(dict)

        // Then
        #expect(output.contains("status: failed"), Comment(rawValue: output))
        #expect(output.contains("error:"), Comment(rawValue: output))
        #expect(output.contains("  type: ShellError"), "nested indentation:\n\(output)")
        #expect(output.contains("  message: exit 1"), Comment(rawValue: output))
    }
    
    @Test("booleans and scalars are printed as-is, without quotes")
    func boolAndScalars() {
        // Given
        let dict: [String: Any] = ["ok": true, "channel": "C09U6LM639R", "ts": "1779.79"]
        let output = renderResultPlain(dict)

        // Then
        #expect(output.contains("ok: true"), "Bool must render as true, not 1:\n\(output)")
        #expect(output.contains("channel: C09U6LM639R"), Comment(rawValue: output))
        #expect(output.contains("ts: 1779.79"), Comment(rawValue: output))
    }
    
    @Test("multi-line values unfold as a block")
    func multilineValueRendersAsBlock() {
        // Given
        let dict: [String: Any] = ["result": ["log": "line one\nline two"]]
        let output = renderResultPlain(dict)

        // Then
        #expect(output.contains("    line one"), "multi-line block indentation:\n\(output)")
        #expect(output.contains("    line two"), Comment(rawValue: output))
    }
    
    @Test("with no outputs, only the status remains")
    func emptyResult() {
        #expect(renderResultPlain([:]) == "(empty result)")
    }
    
    // MARK: - Private
}
