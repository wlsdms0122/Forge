//
//  PipeReader.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

/// Sole owner of one pipe: it creates the descriptor pair, lends the write end to a child,
/// and reclaims both. The read fd is touched by this type's source queue and nothing else,
/// so reading and finishing cannot race over the same descriptor.
final class PipeReader: @unchecked Sendable {
    // MARK: - Property
    /// The write end handed to the child. `closeOnDealloc` is off, so closing it is this type's job.
    let writingHandle: FileHandle
    
    private let readingDescriptor: Int32
    private let writingDescriptor: Int32
    private let source: any DispatchSourceRead
    private let onChunk: (@Sendable (Data) -> Void)?
    private let completion = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var buffer = Data()
    private var writingClosed = false
    
    // MARK: - Initializer
    /// `onChunk` is called on this reader's private serial queue, in arrival order, and blocks
    /// further reading while it runs — it is the only composition point, so keep it cheap.
    init(onChunk: (@Sendable (Data) -> Void)? = nil) throws {
        var descriptors: [Int32] = [-1, -1]
        
        guard pipe(&descriptors) == 0 else { throw PipeReaderError.creationFailed(errno: errno) }
        
        readingDescriptor = descriptors[0]
        writingDescriptor = descriptors[1]
        writingHandle = FileHandle(fileDescriptor: writingDescriptor, closeOnDealloc: false)
        self.onChunk = onChunk
        
        let flags = fcntl(readingDescriptor, F_GETFL)
        
        guard flags >= 0, fcntl(readingDescriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            let failure = errno
            close(readingDescriptor)
            close(writingDescriptor)
            
            throw PipeReaderError.creationFailed(errno: failure)
        }
        
        source = DispatchSource.makeReadSource(
            fileDescriptor: readingDescriptor,
            queue: DispatchQueue(label: "forge.pipe-reader")
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            
            // Nothing more can arrive once every write end is closed — cancelling turns EOF into completion.
            if drain() { source.cancel() }
        }
        
        // The fd must close and waiters must wake even if the owner is already gone — do not go through self.
        let descriptor = readingDescriptor
        let finished = completion
        
        source.setCancelHandler { [weak self] in
            // The cancel handler runs only after any in-flight event handler returns — the one place closing the fd is safe.
            _ = self?.drain()
            close(descriptor)
            finished.signal()
        }
        source.resume()
    }
    
    // MARK: - Public
    /// Closes the parent's copy once the child has inherited the write end. Without this, EOF never arrives.
    func closeWriteEnd() {
        lock.lock()
        
        let alreadyClosed = writingClosed
        writingClosed = true
        
        lock.unlock()
        
        guard !alreadyClosed else { return }
        
        close(writingDescriptor)
    }
    
    /// Ends reading and returns every byte collected so far. Repeated calls return the same value.
    @discardableResult
    func finish() -> Data {
        closeWriteEnd()
        source.cancel()
        completion.wait()
        completion.signal()
        
        lock.lock()
        
        defer { lock.unlock() }
        
        return buffer
    }
    
    // MARK: - Private
    /// Drains whatever is readable. Returns whether the stream has ended.
    private func drain() -> Bool {
        var chunk = Data()
        var bytes = [UInt8](repeating: 0, count: 65536)
        var endOfStream = false
        
        while true {
            // Never trust the descriptor to still be non-blocking: this runs on the teardown path,
            // and one blocking read here would park a thread that `finish()` is waiting on.
            var readable = pollfd(fd: readingDescriptor, events: Int16(POLLIN), revents: 0)
            
            guard poll(&readable, 1, 0) > 0 else { break }
            
            let count = read(readingDescriptor, &bytes, bytes.count)
            
            if count > 0 {
                chunk.append(contentsOf: bytes[0..<count])
            } else if count == 0 {
                endOfStream = true
                
                break
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                break
            } else {
                // Holding on to an unreadable fd leaves the source spinning on empty events.
                endOfStream = true
                
                break
            }
        }
        
        guard !chunk.isEmpty else { return endOfStream }
        
        lock.lock()
        buffer.append(chunk)
        lock.unlock()
        
        onChunk?(chunk)
        
        return endOfStream
    }
    
    deinit {
        // Releasing a source that was never cancelled makes libdispatch kill the process.
        closeWriteEnd()
        source.cancel()
    }
}

enum PipeReaderError: ForgeError, CustomStringConvertible {
    case creationFailed(errno: Int32)
    
    var message: String { description }
    
    var description: String {
        switch self {
        case .creationFailed(let code):
            return "failed to create pipe (errno=\(code))"
        }
    }
}
