//
//  UnixSocketServer.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Darwin

actor UnixSocketServer {
    // MARK: - Property
    let path: String
    
    private var listenFD: Int32 = -1
    private var acceptTask: Task<Void, Never>?
    private var continuation: AsyncStream<Connection>.Continuation?
    
    // MARK: - Initializer
    init(path: String) {
        self.path = path
    }
    
    // MARK: - Public
    nonisolated static func isLive(path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        
        guard fd >= 0 else { return false }
        
        defer { close(fd) }
        
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        
        let bytes = Array(path.utf8)
        
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
        
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: bytes.count + 1) { characters in
                for (index, byte) in bytes.enumerated() {
                    characters[index] = CChar(bitPattern: byte)
                }
                
                characters[bytes.count] = 0
            }
        }
        
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        return result == 0
    }
    
    func start() throws -> AsyncStream<Connection> {
        try? FileManager.default.removeItem(atPath: path)
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        
        guard fd >= 0 else {
            throw ProtocolError("socket() failed: errno=\(errno)")
        }
        
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        
        let pathBytes = Array(path.utf8)
        
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            
            throw ProtocolError("socket path too long: \(path)")
        }
        
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: pathBytes.count + 1
            ) { characters in
                for (index, byte) in pathBytes.enumerated() {
                    characters[index] = CChar(bitPattern: byte)
                }
                
                characters[pathBytes.count] = 0
            }
        }
        
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard bindResult == 0 else {
            let bindErrno = errno
            close(fd)
            
            throw ProtocolError("bind() failed: errno=\(bindErrno)")
        }
        
        guard listen(fd, 32) == 0 else {
            let listenErrno = errno
            close(fd)
            
            throw ProtocolError("listen() failed: errno=\(listenErrno)")
        }
        
        self.listenFD = fd
        
        let stream = AsyncStream<Connection> { continuation in
            self.continuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.stop() }
            }
        }
        let capturedFD = fd
        let publish: @Sendable (Connection) -> Void = { [weak self] connection in
            Task { await self?.publish(connection) }
        }
        
        acceptTask = Task.detached(priority: .userInitiated) {
            var consecutiveFailures = 0
            
            while !Task.isCancelled {
                var clientAddress = sockaddr_un()
                var length: socklen_t = socklen_t(MemoryLayout<sockaddr_un>.size)
                let clientFD = withUnsafeMutablePointer(to: &clientAddress) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                        accept(capturedFD, socketAddress, &length)
                    }
                }
                
                if clientFD < 0 {
                    if errno == EBADF || errno == EINVAL { break }
                    if errno == EINTR { continue }
                    
                    let acceptErrno = errno
                    consecutiveFailures += 1
                    
                    let backoffMs = min(100 << min(consecutiveFailures - 1, 6), 5_000)
                    
                    FileHandle.standardError.write(Data(
                        "forge: accept failed (errno \(acceptErrno), consecutive \(consecutiveFailures)), retrying in \(backoffMs)ms\n".utf8
                    ))
                    
                    try? await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
                    
                    continue
                }
                
                consecutiveFailures = 0
                
                var one: Int32 = 1
                _ = setsockopt(
                    clientFD,
                    SOL_SOCKET,
                    SO_NOSIGPIPE,
                    &one,
                    socklen_t(MemoryLayout<Int32>.size)
                )
                
                publish(Connection(fd: clientFD))
            }
        }
        
        return stream
    }
    
    func stop() {
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        
        acceptTask?.cancel()
        acceptTask = nil
        continuation?.finish()
        continuation = nil
        
        try? FileManager.default.removeItem(atPath: path)
    }
    
    // MARK: - Private
    private func publish(_ connection: Connection) {
        continuation?.yield(connection)
    }
}
