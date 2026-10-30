//
//  StreamJSONReaderTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("StreamJSONReader Tests")
struct StreamJSONReaderTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("tool use and result each carry their own timestamp")
    func toolUseAndToolResultGetSeparateTimestamps() {
        // Given
        let reader = StreamJSON.Reader()
        let firstAt = Date(timeIntervalSince1970: 1_000)
        let secondAt = Date(timeIntervalSince1970: 1_000.5)
        let thirdAt = Date(timeIntervalSince1970: 1_002)
        let fourthAt = Date(timeIntervalSince1970: 1_003)
        reader.feed(line: #"{"type":"system","subtype":"init"}"#, at: firstAt)
        reader.feed(
            line: #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_1","name":"Read","input":{"file_path":"/x"}},{"type":"tool_use","id":"tu_2","name":"Bash","input":{"command":"ls"}}]}}"#,
            at: secondAt
        )
        reader.feed(
            line: #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_2","content":"file1\nfile2","is_error":false}]}}"#,
            at: thirdAt
        )
        reader.feed(
            line: #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_1","content":"hello","is_error":false}]}}"#,
            at: fourthAt
        )
        reader.feed(line: #"{"type":"result","result":"done"}"#, at: fourthAt)
        let snapshot = reader.snapshot()

        // Then
        #expect(snapshot.finalText == "done")
        #expect(snapshot.toolEvents.count == 2)
        let read = snapshot.toolEvents[0]
        #expect(read.name == "Read")
        #expect(read.startedAt == secondAt)
        #expect(read.completedAt == fourthAt)
        #expect(read.durationMs == 2500)
        #expect(read.resultPreview == "hello")
        let bash = snapshot.toolEvents[1]
        #expect(bash.name == "Bash")
        #expect(bash.startedAt == secondAt)
        #expect(bash.completedAt == thirdAt)
        #expect(bash.durationMs == 1500)
    }
    
    @Test("the start time is when the turn arrived")
    func startedAtReflectsTurnArrival() {
        // Given
        let reader = StreamJSON.Reader()
        let bootAt = Date(timeIntervalSince1970: 1_000)
        let secondAt = Date(timeIntervalSince1970: 1_005)
        reader.feed(
            line: #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"a","name":"Read","input":{}}]}}"#,
            at: bootAt
        )
        reader.feed(
            line: #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"a","content":"ok"}]}}"#,
            at: bootAt
        )
        reader.feed(
            line: #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b","name":"Bash","input":{}}]}}"#,
            at: secondAt
        )
        let snapshot = reader.snapshot()

        // Then
        #expect(snapshot.toolEvents.count == 2)
        #expect(snapshot.toolEvents[0].startedAt == bootAt)
        #expect(snapshot.toolEvents[1].startedAt == secondAt)
        let gap = snapshot.toolEvents[1].startedAt!.timeIntervalSince(snapshot.toolEvents[0].startedAt!)
        #expect(abs(gap - 5.0) < 0.001, "gap=\(gap)")
    }
    
    @Test("batch parsing also splits CRLF into lines")
    func batchParseSplitsCRLFLines() {
        // Given
        let lines = [
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}"#,
            #"{"type":"result","result":"end"}"#,
        ]
        let parsed = StreamJSON.parse(lines.joined(separator: "\r\n"))

        // Then
        #expect(parsed.finalText == "end", "CRLF-joined stream-json lines must be split and parsed: \(parsed.finalText)")
    }
    
    @Test("batch parsing has no arrival times — those come only from the stream")
    func batchParseHasNoTimestamps() {
        // Given
        let raw = #"""
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"x","name":"Read","input":{}}]}}
        {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"x","content":"r"}]}}
        {"type":"result","result":"end"}
        """#
        let parsed = StreamJSON.parse(raw)

        // Then
        #expect(parsed.toolEvents.count == 1)
        #expect(parsed.toolEvents[0].startedAt == nil)
        #expect(parsed.toolEvents[0].completedAt == nil)
        #expect(parsed.toolEvents[0].durationMs == nil)
    }
    
    // MARK: - Private
}
