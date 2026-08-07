//
//  LineCodecTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("LineCodec Tests")
struct LineCodecTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("broken UTF-8 frames are passed up, not swallowed")
    func invalidUTF8FrameIsYieldedNotDropped() {
        // Given
        var buffer = LineBuffer()
        var data = Data([0xFF, 0xFE, 0xFF])
        data.append(0x0a)
        data.append(contentsOf: Array(#"{"id":"1"}"#.utf8))
        data.append(0x0a)
        let frames = buffer.append(data)

        // Then
        #expect(frames.count == 2, "invalid-UTF-8 frame was silently dropped during framing")
        #expect(frames[0] == Data([0xFF, 0xFE, 0xFF]))
        #expect(String(data: frames[0], encoding: .utf8) == nil, "frame[0] should indeed be non-UTF-8")
    }
    
    @Test("trims CRLF and reassembles chunks that arrive split")
    func cRLFTrimAndSplitChunkReassembly() {
        // Given
        var buffer = LineBuffer()

        // Then
        #expect(buffer.append(Data("ab".utf8)).count == 0, "no newline yet → no frame")
        #expect(buffer.append(Data("c\r\n".utf8)) == [Data("abc".utf8)], "\\r\\n trim / reassembly broke")
    }
    
    @Test("non-UTF-8 frames are rejected, not silently passed along")
    func decodeRejectsNonUTF8FrameLoudly() {
        #expect(throws: (any Error).self, "non-UTF-8 frame must throw so the caller logs rpc.malformed") { try RPCRequest.decode(Data([0xFF, 0xFE, 0xFF])) }
    }
    
    @Test("a valid frame is parsed as-is")
    func decodeParsesValidFrame() throws {
        // Given
        let request = try RPCRequest.decode(Data(#"{"id":"1","method":"ping","params":{}}"#.utf8))

        // Then
        #expect(request.id == "1")
        #expect(request.method == "ping")
    }
    
    // MARK: - Private
}
