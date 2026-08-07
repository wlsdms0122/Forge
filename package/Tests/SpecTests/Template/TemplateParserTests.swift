//
//  TemplateParserTests.swift
//  SpecTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Spec

@Suite
struct TemplateParserTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("a mixed template splits into text and ref segments")
    func mixedTemplateSplitsRefsAndText() throws {
        // Given
        let sut = TemplateParser()

        // When
        let segments = try sut.parse("a=${x.y}, b=${z}")

        // Then
        #expect(segments == [
            .text("a="),
            .ref(path: [.key("x"), .key("y")]),
            .text(", b="),
            .ref(path: [.key("z")])
        ])
    }

    @Test("a doubled dollar escapes to a literal dollar")
    func doubledDollarEscapes() throws {
        // Given
        let sut = TemplateParser()

        // When
        let segments = try sut.parse("cost: $$5 and ${price}")

        // Then
        #expect(segments == [.text("cost: $5 and "), .ref(path: [.key("price")])])
    }

    @Test("a bracketed path parses into index segments")
    func bracketPathParsesIndexSegments() throws {
        // Given
        let sut = TemplateParser()

        // When
        let parsed = try sut.parseRefPath("items[0].name[${i}]")

        // Then
        #expect(parsed == [.key("items"), .index(0), .key("name"), .indexRef([.key("i")])])
    }

    @Test("render restores segments to the original text")
    func renderRoundTripsSegments() throws {
        // Given
        let sut = TemplateParser()
        let text = "a=${x.y[0]} $$ b"

        // When
        let rendered = sut.render(try sut.parse(text))

        // Then
        #expect(rendered == text)
    }
}
