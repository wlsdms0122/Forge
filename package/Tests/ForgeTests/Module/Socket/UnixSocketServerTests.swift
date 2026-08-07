//
//  UnixSocketServerTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("UnixSocketServer Tests")
struct UnixSocketServerTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("with no socket file, answers not live")
    func isLiveFalseForAbsentSocket() {
        // Given
        let path = "/tmp/forge-absent-\(UUID().uuidString.prefix(8)).sock"

        // Then
        #expect(!UnixSocketServer.isLive(path: path), "a path nobody listens on is not live")
    }
    
    @Test("a leftover stale socket file is not reported as live")
    func isLiveFalseForStaleSocketFile() throws {
        // Given
        let path = "/tmp/forge-stale-\(UUID().uuidString.prefix(8)).sock"
        FileManager.default.createFile(atPath: path, contents: Data())
        defer { try? FileManager.default.removeItem(atPath: path) }

        // Then
        #expect(!UnixSocketServer.isLive(path: path), "socket connect fails on a regular file")
    }
    
    // MARK: - Private
}
