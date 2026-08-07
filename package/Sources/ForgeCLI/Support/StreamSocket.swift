//
//  StreamSocket.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Forge

#if canImport(Darwin)
import Darwin
#endif

final class StreamSocket: @unchecked Sendable {
    // MARK: - Property
    private let fd: Int32
    
    private var lineBuffer = LineBuffer()
    private var pending: [Data] = []
    private var eof = false
    
    // MARK: - Initializer
    init?(path: String) {
        guard let fd = Self.connect(path: path) else { return nil }
        
        self.fd = fd
    }
    
    // MARK: - Public
    func writeLine(_ data: Data) -> Bool {
        var line = data
        line.append(0x0a)
        
        return line.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
            var written = 0
            
            while written < line.count {
                let count = write(
                    fd,
                    buffer.baseAddress!.advanced(by: written),
                    line.count - written
                )
                
                if count <= 0 { return false }
                
                written += count
            }
            
            return true
        }
    }
    
    func readFrame() -> Data? {
        while true {
            if !pending.isEmpty { return pending.removeFirst() }
            if eof { return nil }
            
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            let count = chunk.withUnsafeMutableBufferPointer { buffer in
                read(fd, buffer.baseAddress, buffer.count)
            }
            
            if count <= 0 {
                eof = true
                
                continue
            }
            
            pending.append(contentsOf: lineBuffer.append(Data(chunk[0..<count])))
        }
    }
    
    func close() {
        Darwin.close(fd)
    }
    
    // MARK: - Private
    private static func connect(path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        
        guard fd >= 0 else { return nil }
        
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        
        let pathBytes = Array(path.utf8)
        
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(fd)
            
            return nil
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
        
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard result == 0 else {
            Darwin.close(fd)
            
            return nil
        }
        
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        
        return fd
    }
}

func emitStdoutLine(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
}

func emitStderr(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}
