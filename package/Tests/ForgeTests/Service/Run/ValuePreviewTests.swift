//
//  ValuePreviewTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import Forge

@Suite("ValuePreview Tests")
struct ValuePreviewTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test(
        "a value previews as its JSON text, a string as its own text",
        arguments: [
            (JSONValue.int(42), "42", 2),
            (.bool(true), "true", 4),
            (.double(1.5), "1.5", 3),
            (.string("hi"), "hi", 2),
            (.object(["a": .int(1)]), #"{"a":1}"#, 7)
        ] as [(JSONValue, String, Int)]
    )
    func aValuePreviewsAsItsText(value: JSONValue, text: String, length: Int) throws {
        // When
        let sut = try #require(ValuePreview(value))

        // Then
        #expect(sut.text == text)
        #expect(sut.length == length)
    }

    @Test("null has no preview")
    func nullHasNoPreview() {
        // When
        let sut = ValuePreview(.null)

        // Then
        #expect(sut == nil)
    }

    @Test("a long text is cut to the limit, and its length counts the whole text")
    func aLongTextIsCut() throws {
        // Given
        let long = String(repeating: "x", count: 3000)

        // When
        let sut = try #require(ValuePreview(.string(long)))

        // Then
        #expect(sut.text.count == ValuePreview.limit)
        #expect(sut.length == 3000)
    }

    // MARK: - Public
    // MARK: - Private
}
