//
//  PipeReaderTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("PipeReader Tests")
struct PipeReaderTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("finish returns every byte fed through the write end")
    func finishReturnsEveryByteWritten() throws {
        // Given
        let sut = try PipeReader()
        let payload = Data(repeating: UInt8(ascii: "x"), count: 200_000)

        // When
        try sut.writingHandle.write(contentsOf: payload)
        let collected = sut.finish()

        // Then
        #expect(collected == payload)
    }

    @Test("finish is idempotent — repeated calls return the same value")
    func finishIsIdempotent() throws {
        // Given
        let sut = try PipeReader()

        // When
        try sut.writingHandle.write(contentsOf: Data("hello".utf8))
        let first = sut.finish()
        let second = sut.finish()

        // Then
        #expect(first == Data("hello".utf8))
        #expect(second == first)
    }

    @Test("a closed write end ends the reader by itself — finish never hangs")
    func finishReturnsAfterWriteEndCloses() throws {
        // Given
        let sut = try PipeReader()

        // When
        try sut.writingHandle.write(contentsOf: Data("tail".utf8))
        sut.closeWriteEnd()
        let collected = sut.finish()

        // Then
        #expect(collected == Data("tail".utf8))
    }

    @Test("arriving bytes flow to the callback in order")
    func chunksReachTheCallbackInArrivalOrder() throws {
        // Given
        let collector = OrderedCollector<Data>()
        let sut = try PipeReader { chunk in collector.append(chunk) }

        // When
        for index in 0..<20 {
            try sut.writingHandle.write(contentsOf: Data("frame-\(index);".utf8))
        }

        let collected = sut.finish()

        // Then
        let fed = collector.elements.reduce(Data()) { joined, chunk in joined + chunk }
        #expect(fed == collected)
        #expect(String(decoding: fed, as: UTF8.self).hasPrefix("frame-0;frame-1;"))
    }

    // MARK: - Private
}
