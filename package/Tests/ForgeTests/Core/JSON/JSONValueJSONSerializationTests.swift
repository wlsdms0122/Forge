//
//  JSONValueJSONSerializationTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/25/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("JSONValue JSONSerialization Tests")
struct JSONValueJSONSerializationTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("A JSON object read from Foundation keeps every case, and a whole number is an int")
    func readsFoundationObjects() throws {
        // Given
        let object: [String: Any] = [
            "text": "a",
            "count": 2,
            "whole": 5.0,
            "ratio": 0.5,
            "flag": true,
            "none": NSNull(),
            "list": [1, "b"]
        ]

        // When
        let sut = try JSONValue(jsonObject: object)

        // Then
        #expect(sut == [
            "text": "a",
            "count": 2,
            "whole": 5,
            "ratio": 0.5,
            "flag": true,
            "none": .null,
            "list": [1, "b"]
        ])
    }

    @Test("A value written through Foundation is the bytes the same Foundation object writes")
    func writesTheSameBytes() throws {
        // Given
        let object: [String: Any] = ["b": [1, 2.5, "x/y"], "a": true, "c": NSNull()]
        let sut = try JSONValue(jsonObject: object)
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]

        // When
        let written = try JSONSerialization.data(withJSONObject: sut.jsonObject, options: options)

        // Then
        #expect(written == (try JSONSerialization.data(withJSONObject: object, options: options)))
    }

    // MARK: - Public
    // MARK: - Private
}
