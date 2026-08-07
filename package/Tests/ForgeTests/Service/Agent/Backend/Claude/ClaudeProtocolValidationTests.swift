//
//  ClaudeProtocolValidationTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("ClaudeProtocolValidation Tests")
struct ClaudeProtocolValidationTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    // MARK: reader counts what it drops
    @Test("structurally broken frames are counted, not silently dropped")
    func structurallyInvalidFrameIsCountedNotSilentlyDropped() {
        // Given
        let reader = StreamJSON.Reader()
        reader.feed(line: "this is not json at all", at: .fixture)
        reader.feed(line: "{\"unterminated\": ", at: .fixture)
        reader.feed(line: "[1, 2, 3]", at: .fixture)

        // Then
        #expect(reader.snapshot().malformedLineCount == 3, "valid-UTF8 non-event frames were dropped without a trace")
    }
    
    @Test("an empty line is not a broken frame")
    func blankLinesAreNotMalformed() {
        let reader = StreamJSON.Reader()
        reader.feed(line: "", at: .fixture)
        reader.feed(line: "   ", at: .fixture)
        #expect(reader.snapshot().malformedLineCount == 0, "NDJSON padding is not a protocol violation")
    }
    
    @Test("non-UTF-8 frames join the same malformed count")
    func nonUTF8FramesJoinTheSameMalformedCount() {
        var frame = Data(#"{"type":"result","result":"ok-"#.utf8)
        frame.append(0xFF)
        frame.append(contentsOf: Data(#""}"#.utf8))
        let reader = StreamJSON.Reader()
        reader.feed(frame: frame, at: .fixture)
        #expect(reader.snapshot().malformedLineCount == 1, "the two corruption channels must report through one number")
    }
    
    // MARK: terminal result is observed, never assumed
    @Test("observes the terminal result frame")
    func terminalResultIsObserved() {
        let reader = StreamJSON.Reader()
        reader.feed(line: #"{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}"#, at: .fixture)
        #expect(!reader.snapshot().sawTerminalResult, "assistant frames alone are a truncated stream, not a completed turn")
        reader.feed(line: #"{"type":"result","result":"hi"}"#, at: .fixture)
        #expect(reader.snapshot().sawTerminalResult)
    }
    
    // MARK: the success condition
    @Test("protocol violations cannot be absorbed by fallback")
    func protocolViolationIsNotFallbackAbsorbable() throws {
        let reader = StreamJSON.Reader()
        reader.feed(line: "garbage", at: .fixture)
        reader.feed(line: #"{"type":"result","result":"hi"}"#, at: .fixture)
        let error = try #require(throws: (any Error).self) {
            try ClaudeBackend.validateSuccessfulProtocol(reader.snapshot())
        }
        
        #expect(!(error is any WorkFailure), "a protocol violation is 'we cannot know what happened', not 'the work failed'")
        #expect(error is BackendProtocolViolation, "unexpected: \(type(of: error))")
    }
    
    @Test("both backends use the same violation type — classification does not diverge")
    func bothBackendsUseTheSameViolationType() throws {
        let claude = StreamJSON.Reader()
        claude.feed(line: "garbage", at: .fixture)
        let codex = CodexEventStream.Reader()
        codex.feed(line: "garbage", at: .fixture)
        let claudeError = try #require(throws: (any Error).self) {
            try ClaudeBackend.validateSuccessfulProtocol(claude.snapshot())
        }
        let codexError = try #require(throws: (any Error).self) {
            try CodexBackend.validateSuccessfulProtocol(codex.snapshot())
        }
        
        #expect(claudeError is BackendProtocolViolation)
        #expect(codexError is BackendProtocolViolation)
    }
    
    @Test("streams containing broken frames are rejected")
    func validateRejectsMalformedFrames() throws {
        let reader = StreamJSON.Reader()
        reader.feed(line: "garbage", at: .fixture)
        reader.feed(line: #"{"type":"result","result":"hi"}"#, at: .fixture)
        let error = try #require(throws: (any Error).self) {
            try ClaudeBackend.validateSuccessfulProtocol(reader.snapshot())
        }
        
        #expect("\(error)".contains("malformed"), "unexpected: \(error)")
    }
    
    @Test("streams without a terminal result are rejected")
    func validateRejectsAStreamWithNoTerminalResult() throws {
        let reader = StreamJSON.Reader()
        reader.feed(line: #"{"type":"assistant","message":{"content":[{"type":"text","text":"partial"}]}}"#, at: .fixture)
        let error = try #require(throws: (any Error).self) {
            try ClaudeBackend.validateSuccessfulProtocol(reader.snapshot())
        }
        
        #expect("\(error)".contains("terminal result"), "unexpected: \(error)")
    }
    
    @Test("output that is not the protocol at all is rejected")
    func validateRejectsAnEntirelyNonProtocolStream() {
        let reader = StreamJSON.Reader()
        for line in ["hello", "there is no json here", "just prose"] {
            reader.feed(line: line, at: .fixture)
        }
        
        let snapshot = reader.snapshot()
        #expect(snapshot.finalText.isEmpty, "noise must not become the answer")
        #expect(throws: (any Error).self) { try ClaudeBackend.validateSuccessfulProtocol(snapshot) }
    }
    
    @Test("well-formed turns pass")
    func validateAcceptsAWellFormedTurn() throws {
        let reader = StreamJSON.Reader()
        reader.feed(line: #"{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}"#, at: .fixture)
        reader.feed(line: #"{"type":"result","result":"hi","usage":{"input_tokens":3}}"#, at: .fixture)
        let snapshot = reader.snapshot()
        #expect(throws: Never.self) { try ClaudeBackend.validateSuccessfulProtocol(snapshot) }
        #expect(snapshot.finalText == "hi")
    }
    
    @Test("turns with only tool calls also count as normal")
    func validateAcceptsAToolOnlyTurn() {
        let reader = StreamJSON.Reader()
        reader.feed(
            line: #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{}}]}}"#,
            at: .fixture)
        reader.feed(
            line: #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}"#,
            at: .fixture)
        reader.feed(line: #"{"type":"result","result":""}"#, at: .fixture)
        let snapshot = reader.snapshot()
        #expect(!snapshot.toolEvents.isEmpty, "the premise of this case — tools ran and only the text is missing")
        #expect(snapshot.finalText.isEmpty)
        #expect(throws: Never.self) { try ClaudeBackend.validateSuccessfulProtocol(snapshot) }
    }
    
    @Test("turns with nothing observed are rejected")
    func validateRejectsATurnWhereNothingWasObserved() throws {
        let reader = StreamJSON.Reader()
        reader.feed(line: #"{"type":"result","result":""}"#, at: .fixture)
        let error = try #require(throws: (any Error).self) {
            try ClaudeBackend.validateSuccessfulProtocol(reader.snapshot())
        }
        
        #expect(error is BackendProtocolViolation, "\(error)")
    }
    
    // MARK: The verdict does not weaken as damage worsens
    @Test("worse damage is not demoted to an absorbable failure")
    func worseCorruptionIsNotDowngradedToAnAbsorbableFailure() throws {
        let nothing = StreamJSON.Reader()
        nothing.feed(frame: Data([0xFF, 0xFE]), at: .fixture)
        let nothingSnap = nothing.snapshot()
        #expect(nothingSnap.finalText.isEmpty && nothingSnap.toolEvents.isEmpty)
        let partial = StreamJSON.Reader()
        partial.feed(frame: Data([0xFF, 0xFE]), at: .fixture)
        partial.feed(line: #"{"type":"result","result":"hi"}"#, at: .fixture)
        for snapshot in [nothingSnap, partial.snapshot()] {
            let error = try #require(throws: (any Error).self) {
                try ClaudeBackend.validateSuccessfulProtocol(snapshot)
            }
            
            #expect(error is BackendProtocolViolation, "must be the same class regardless of damage severity: \(error)")
            #expect(!(error is any WorkFailure), "a contract violation must not be absorbed by the fallback budget")
        }
    }
    
    // MARK: - Private
}
