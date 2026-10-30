//
//  RPCTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge
@testable import ForgeCLI

@Suite("RPC Tests")
struct RPCTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
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
        
        #expect(result["v"]?.intValue == 1)
    }
    
    // MARK: - Private
}
