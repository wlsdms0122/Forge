//
//  LineSplitter.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

final class LineSplitter: @unchecked Sendable {
    // MARK: - Property
    private let lock = NSLock()
    private let handler: Subprocess.StdoutLineHandler
    private var carry = Data()
    
    // MARK: - Initializer
    init(handler: @escaping Subprocess.StdoutLineHandler) {
        self.handler = handler
    }
    
    // MARK: - Public
    func feed(_ data: Data, at now: Date) {
        lock.lock()
        carry.append(data)
        
        var lines: [Data] = []
        
        while let newlineIndex = carry.firstIndex(of: 0x0A) {
            let lineData = carry.subdata(in: carry.startIndex..<newlineIndex)
            carry.removeSubrange(carry.startIndex...newlineIndex)
            
            if lineData.last == 0x0D {
                lines.append(
                    lineData.subdata(
                        in: lineData.startIndex..<lineData.index(before: lineData.endIndex)
                    )
                )
            } else {
                lines.append(lineData)
            }
        }
        
        lock.unlock()
        
        for line in lines { handler(line, now) }
    }
    
    func flushRemainder(at now: Date) {
        lock.lock()
        
        let remaining = carry
        carry = Data()
        
        lock.unlock()
        
        guard !remaining.isEmpty else { return }
        
        handler(remaining, now)
    }
    
    // MARK: - Private
}
