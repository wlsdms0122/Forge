//
//  Connection.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Darwin

actor Connection {
    // MARK: - Property
    let id: UUID = UUID()
    
    private let fd: Int32
    private let writeQueue = DispatchQueue(label: "forge.conn.write")
    
    private var lineBuffer = LineBuffer()
    private var continuation: AsyncStream<Data>.Continuation?
    private var readTask: Task<Void, Never>?
    private var started = false
    private var closed = false
    
    // MARK: - Initializer
    init(fd: Int32) {
        self.fd = fd
    }
    
    // MARK: - Public
    func frames() -> AsyncStream<Data> {
        let stream = AsyncStream<Data> { continuation in
            self.continuation = continuation
        }
        
        if !started {
            started = true
            spawnReadLoop()
        }
        
        return stream
    }
    
    func send(_ data: Data) async {
        guard !closed else { return }
        
        let capturedFD = fd
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writeQueue.async {
                _ = data.withUnsafeBytes { buffer -> Int in
                    var written = 0
                    
                    while written < buffer.count {
                        let count = write(
                            capturedFD,
                            buffer.baseAddress!.advanced(by: written),
                            buffer.count - written
                        )
                        
                        if count <= 0 { break }
                        
                        written += count
                    }
                    
                    return written
                }
                
                continuation.resume()
            }
        }
    }
    
    func close() {
        finish()
    }
    
    // MARK: - Private
    private func spawnReadLoop() {
        let capturedFD = fd
        
        readTask = Task.detached(priority: .userInitiated) { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            
            while !Task.isCancelled {
                let count = buffer.withUnsafeMutableBufferPointer { pointer in
                    read(capturedFD, pointer.baseAddress, pointer.count)
                }
                
                if count > 0 {
                    await self?.absorb(Data(buffer[0..<count]))
                } else {
                    await self?.finish()
                    
                    break
                }
            }
        }
    }
    
    private func absorb(_ data: Data) {
        for frame in lineBuffer.append(data) {
            continuation?.yield(frame)
        }
    }
    
    private func finish() {
        guard !closed else { return }
        
        closed = true
        
        let capturedFD = fd
        writeQueue.async { _ = Darwin.close(capturedFD) }
        
        continuation?.finish()
        continuation = nil
        readTask?.cancel()
        readTask = nil
    }
}
