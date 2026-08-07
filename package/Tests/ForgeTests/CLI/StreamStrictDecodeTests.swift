//
//  StreamStrictDecodeTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge
@testable import ForgeCLI

@Suite("StreamStrictDecode Tests")
struct StreamStrictDecodeTests {
    // MARK: - Property
    private var invalidUTF8Frame: Data {
        var frame = Data(#"{"type":"result","result":"ok-"#.utf8)
        frame.append(0xFF)
        frame.append(contentsOf: Data(#""}"#.utf8))
        
        return frame
    }
    
    // MARK: - Initializer
    // MARK: - Test
    @Test("the claude reader counts broken frames instead of repairing them")
    func claudeReaderCountsInvalidFrameInsteadOfRepairing() {
        // Given
        let reader = StreamJSON.Reader()
        reader.feed(frame: invalidUTF8Frame, at: .fixture)

        // Then
        #expect(reader.snapshot().malformedLineCount == 1, "corrupted frames must be counted and dropped — accepting U+FFFD-repaired frames is forbidden")
        #expect(reader.snapshot().finalText.isEmpty, "a repaired result must not be accepted")
        reader.feed(frame: Data(#"{"type":"result","result":"fine"}"#.utf8), at: .fixture)
        #expect(reader.snapshot().finalText == "fine")
        #expect(reader.snapshot().malformedLineCount == 1)
    }
    
    @Test("the codex reader also counts broken frames as malformed")
    func codexReaderCountsInvalidFrameAsMalformed() {
        // Given
        let reader = CodexEventStream.Reader()
        reader.feed(frame: invalidUTF8Frame, at: .fixture)

        // Then
        #expect(reader.snapshot().malformedLineCount == 1, "non-UTF8 frames must join the existing malformed fail-loud mechanism")
    }
    
    @Test("RPC frames reject invalid UTF-8 instead of laundering it")
    func rPCParseFrameRejectsInvalidUTF8InsteadOfLaundering() {
        // Given
        var frame = Data(#"{"result":{"value":""#.utf8)
        frame.append(0xFF)
        frame.append(contentsOf: Data(#""}}"#.utf8))
        guard case .err(let type, let message) = RPC.parseFrame(frame) else {

        // Then
            Issue.record("a corrupted frame must not be laundered into .ok")
            
            return
        }
        
        #expect(type == "ClientError")
        #expect(message.contains("malformed"), Comment(rawValue: message))
        guard case .ok(let result) = RPC.parseFrame(Data(#"{"result":{"v":1}}"#.utf8)) else {
            Issue.record("a valid frame must be ok")
            
            return
        }
        
        #expect(result["v"] as? Int == 1)
    }
    
    // MARK: - Private
}
