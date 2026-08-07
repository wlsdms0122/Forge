//
//  ConnectionCloseTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
import Darwin
@testable import Forge

@Suite("ConnectionClose Tests")
struct ConnectionCloseTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("a send after close does not write to a reused fd")
    func sendAfterCloseDoesNotWriteToReusedFD() async throws {
        // Given
        var fds: [Int32] = [0, 0]

        // Then
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        let (ours, peer) = (fds[0], fds[1])
        let conn = Connection(fd: ours)
        let drain = Task { for await _ in await conn.frames() {} }
        Darwin.close(peer)
        _ = await drain.value
        try await Task.sleep(nanoseconds: 100_000_000)
        var pipeFDs: [Int32] = [0, 0]
        #expect(pipe(&pipeFDs) == 0)
        #expect(dup2(pipeFDs[1], ours) == ours)
        defer { Darwin.close(pipeFDs[0]); Darwin.close(pipeFDs[1]); Darwin.close(ours) }
        await conn.send(Data("late-write-must-not-appear\n".utf8))
        let flags = fcntl(pipeFDs[0], F_GETFL)
        _ = fcntl(pipeFDs[0], F_SETFL, flags | O_NONBLOCK)
        var buffer = [UInt8](repeating: 0, count: 128)
        let bytesRead = read(pipeFDs[0], &buffer, buffer.count)
        #expect(bytesRead <= 0, "a late send on a closed connection leaked into a reused fd: \(String(decoding: buffer.prefix(max(bytesRead, 0)), as: UTF8.self))")
    }
    
    @Test("writes made before close are flushed before closing")
    func writesBeforeCloseAreFlushed() async throws {
        // Given
        var fds: [Int32] = [0, 0]

        // Then
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        let (ours, peer) = (fds[0], fds[1])
        defer { Darwin.close(peer) }
        let conn = Connection(fd: ours)
        await conn.send(Data("hello\n".utf8))
        await conn.close()
        var buffer = [UInt8](repeating: 0, count: 64)
        let bytesRead = read(peer, &buffer, buffer.count)
        #expect(String(decoding: buffer.prefix(max(bytesRead, 0)), as: UTF8.self) == "hello\n")
    }
    
    // MARK: - Private
}
