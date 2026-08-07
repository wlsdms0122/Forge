//
//  LineCodec.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

package struct LineBuffer: Sendable {
    // MARK: - Property
    private var buffer: Data = Data()
    
    // MARK: - Initializer
    package init() {}
    
    // MARK: - Public
    package mutating func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        
        var lines: [Data] = []
        
        while let newlineIndex = buffer.firstIndex(of: 0x0a) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            let trimmed: Data
            
            if let last = lineData.last, last == 0x0d {
                trimmed = lineData.dropLast()
            } else {
                trimmed = lineData
            }
            
            lines.append(Data(trimmed))
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
        }
        
        return lines
    }
    
    // MARK: - Private
}
