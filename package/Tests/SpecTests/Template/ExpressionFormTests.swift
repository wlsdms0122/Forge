//
//  ExpressionFormTests.swift
//  SpecTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Spec

@Suite
struct ExpressionFormTests {
    // MARK: - Property
    private let loader = SpecLoader.testing

    // MARK: - Initializer
    // MARK: - Test
    @Test("a string spelling a placeholder stays a literal")
    func placeholderStringStaysLiteral() throws {
        // Given — the injection doctrine: no string is ever re-parsed into a ref
        let reference = try loader.decode(
            Reference.self,
            from: Data("\"${inputs.secret}\"".utf8)
        )

        // Then
        guard case .stringValue(let string) = reference else {
            Issue.record("expected stringValue, got \(reference)")

            return
        }

        #expect(string == "${inputs.secret}")
        #expect(reference.referencedPaths.isEmpty)
    }

    @Test("only the exact { ref: } form decodes as a reference")
    func exactRefFormDecodes() throws {
        // Given
        let reference = try loader.decode(
            Reference.self,
            from: Data("ref: items[0].name".utf8)
        )

        // Then
        #expect(reference.refPath == [.key("items"), .index(0), .key("name")])
    }

    @Test("form-shaped data inside { value: } quotation stays inert")
    func quotedFormShapedPayloadStaysInert() throws {
        // Given — { value: } is quotation; ref-shaped data inside is data
        let reference = try loader.decode(Reference.self, from: Data("""
        value:
          ref: inputs.secret
        """.utf8))

        // Then
        guard case .quoted(let payload) = reference else {
            Issue.record("expected quoted, got \(reference)")

            return
        }

        #expect(payload == .object(["ref": .string("inputs.secret")]))
        #expect(reference.referencedPaths.isEmpty, "quoted payloads are not even validation targets")
    }

    @Test("a half-spelled form record is rejected at load", arguments: [
        "{ ref: a, extra: b }",
        "{ ref: 3 }",
        "{ value: a, extra: b }",
        "{ with: { a: 1 } }",
        "{ format: \"x\", extra: b }",
        "{ format: \"x\", with: [1, 2] }",
        "{ format: [a], with: { a: 1 } }"
    ])
    func ambiguousFormRecordRejected(yaml: String) {
        // When / Then — a half-spelled form is an author mistake, not a record;
        // plain data carrying these keys must be quoted with { value: }
        #expect(throws: DecodingError.self) {
            _ = try loader.decode(Reference.self, from: Data(yaml.utf8))
        }
    }

    @Test("a placeholder undeclared in `with` is rejected")
    func undeclaredPlaceholderRejected() {
        // Given — the format surface is closed over its `with` bindings
        let yaml = """
        format: "hello, ${who} from ${where}"
        with:
          who: { ref: inputs.who }
        """

        // When / Then
        #expect(throws: DecodingError.self) {
            _ = try loader.decode(Reference.self, from: Data(yaml.utf8))
        }
    }

    @Test("a closed format template decodes")
    func closedFormatDecodes() throws {
        // Given
        let reference = try loader.decode(Reference.self, from: Data("""
        format: "hello, ${who}"
        with:
          who: { ref: inputs.who }
        """.utf8))

        // Then — outward references are the binding expressions, never the template
        #expect(reference.referencedPaths == [[.key("inputs"), .key("who")]])
    }

    @Test("an ordinary record without form keys passes unquoted")
    func plainRecordPassesWithoutFormKeys() throws {
        // Given — an ordinary record of expressions needs no quoting
        let reference = try loader.decode(Reference.self, from: Data("""
        name: report
        target: { ref: inputs.target }
        """.utf8))

        // Then
        guard case .recordValue(let record) = reference else {
            Issue.record("expected recordValue, got \(reference)")

            return
        }

        #expect(record["target"]?.refPath == [.key("inputs"), .key("target")])
    }

    @Test("forms survive the encode-decode round trip")
    func formsSurviveRoundTrip() throws {
        // Given
        let reference = try loader.decode(Reference.self, from: Data("""
        message:
          format: "hi, ${who}"
          with:
            who: { ref: inputs.who }
        payload: { value: { ref: kept-as-data } }
        target: { ref: "steps[0].id" }
        """.utf8))

        // When
        let data = try JSONEncoder().encode(reference)
        let reloaded = try JSONDecoder().decode(Reference.self, from: data)

        // Then
        guard case .recordValue(let record) = reloaded else {
            Issue.record("expected recordValue, got \(reloaded)")

            return
        }

        #expect(record["target"]?.refPath == [.key("steps"), .index(0), .key("id")])

        guard case .quoted(let payload)? = record["payload"] else {
            Issue.record("expected quoted payload")

            return
        }

        #expect(payload == .object(["ref": .string("kept-as-data")]))

        guard case .format(let segments, let with)? = record["message"] else {
            Issue.record("expected format message")

            return
        }

        #expect(segments == [.text("hi, "), .ref(path: [.key("who")])])
        #expect(with["who"]?.refPath == [.key("inputs"), .key("who")])
    }

    @Test("a ${} string stays a literal across repeated round trips")
    func dollarStringStaysLiteralAcrossRoundTrip() throws {
        // Given — a string is a literal; "${a}" needs no escape and must never
        // become a live ref, decode after decode
        let reference = try loader.decode(Reference.self, from: Data("\"${a}\"".utf8))
        let encoder = JSONEncoder()

        // When
        let data = try encoder.encode(reference)
        let reloaded = try JSONDecoder().decode(Reference.self, from: data)

        // Then
        #expect(reloaded.refPath == nil)

        guard case .stringValue(let string) = reloaded else {
            Issue.record("expected stringValue, got \(reloaded)")

            return
        }

        #expect(string == "${a}")
    }
}
