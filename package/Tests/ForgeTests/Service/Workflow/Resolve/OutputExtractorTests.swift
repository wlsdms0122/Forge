//
//  OutputExtractorTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("OutputExtractor Tests")
struct OutputExtractorTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    // MARK: - JSONPath extraction
    @Test("The path extractor pulls out scalars")
    func pathExtractsScalar() throws {
        // Given
        let stdout = #"{"value1":"hello","value2":42}"#
        let declarations: [String: OutputSpec] = [
            "v1": OutputSpec(extractor: .path("$.value1")),
            "v2": OutputSpec(extractor: .path("$.value2"), type: .int),
        ]

        // When
        let output = try OutputExtractor.extract(stdout: stdout, declarations: declarations)

        // Then
        let object = try #require(output.objectValue, "expected object")
        
        #expect(object["v1"] == .string("hello"))
        #expect(object["v2"] == .int(42))
        #expect(object["_raw"] == .string(stdout))
    }
    
    @Test("Nested paths are extracted too")
    func pathExtractsNested() throws {
        // Given
        let stdout = #"{"a":{"b":{"c":"deep"}}}"#
        let declarations = ["x": OutputSpec(extractor: .path("$.a.b.c"))]

        // When
        let output = try OutputExtractor.extract(stdout: stdout, declarations: declarations)

        // Then
        let object = try #require(output.objectValue, "expected object")
        let text = try #require(object["x"]?.stringValue, "expected object.x string")
        
        #expect(text == "deep")
    }
    
    @Test("Array indices are extracted too — including negative indices")
    func pathArrayIndex() throws {
        // Given
        let stdout = #"{"arr":["x","y","z"]}"#
        let declarations = ["first": OutputSpec(extractor: .path("$.arr[0]")),
            "last":  OutputSpec(extractor: .path("$.arr[-1]"))]

        // When
        let output = try OutputExtractor.extract(stdout: stdout, declarations: declarations)

        // Then
        let object = try #require(output.objectValue)
        
        #expect(object["first"] == .string("x"))
        #expect(object["last"] == .string("z"))
    }
    
    // MARK: - regex / line
    @Test("Extracts with a regex")
    func regexExtract() throws {
        // Given
        let stdout = "X-Total: 42\nX-Other: ignored"
        let declarations = ["count": OutputSpec(extractor: .regex(#"^X-Total:\s*(\d+)$"#), type: .int)]

        // When
        let output = try OutputExtractor.extract(stdout: stdout, declarations: declarations)

        // Then
        let object = try #require(output.objectValue)
        
        #expect(object["count"] == .int(42))
    }
    
    @Test("Extracts by line number")
    func lineExtract() throws {
        // Given
        let stdout = "first\nsecond\nthird\n"
        let declarations: [String: OutputSpec] = [
            "head": OutputSpec(extractor: .line(0)),
            "mid":  OutputSpec(extractor: .line(1)),
            "tail": OutputSpec(extractor: .line(-1)),
        ]

        // When
        let output = try OutputExtractor.extract(stdout: stdout, declarations: declarations)

        // Then
        let object = try #require(output.objectValue)
        
        #expect(object["head"] == .string("first"))
        #expect(object["mid"] == .string("second"))
        #expect(object["tail"] == .string("third"))
    }
    
    // MARK: - optional / default
    @Test("A missing optional item is null")
    func optionalMissingReturnsNull() throws {
        // Given
        let stdout = #"{"a":1}"#
        let declarations = ["b": OutputSpec(extractor: .path("$.b"), default: .null)]

        // When
        let output = try OutputExtractor.extract(stdout: stdout, declarations: declarations)

        // Then
        let object = try #require(output.objectValue)
        
        #expect(object["b"] == .null)
    }
    
    @Test("Uses the default value when one is set")
    func optionalMissingUsesDefault() throws {
        // Given
        let stdout = #"{"a":1}"#
        let declarations = ["b": OutputSpec(extractor: .path("$.b"),
                default: .string("fallback"))]

        // When
        let output = try OutputExtractor.extract(stdout: stdout, declarations: declarations)

        // Then
        let object = try #require(output.objectValue)
        
        #expect(object["b"] == .string("fallback"))
    }
    
    @Test("Defaults also pass through the type-coercion gate")
    func defaultGoesThroughCoerceGate() throws {
        // Given
        let stdout = #"{"a":1}"#
        let declarations = ["b": OutputSpec(extractor: .path("$.b"), type: .int,
                default: .string("0"))]

        // When
        let output = try OutputExtractor.extract(stdout: stdout, declarations: declarations)

        // Then
        let object = try #require(output.objectValue)
        
        #expect(object["b"] == .int(0), "The default should also be coerced to the declared type")
    }
    
    @Test("An uncoercible default fails instead of passing silently")
    func uncoercibleDefaultFailsLoud() throws {
        // Given
        let stdout = #"{"a":1}"#
        let declarations = ["b": OutputSpec(extractor: .path("$.b"), type: .int,
                default: .string("nope"))]

        // Then
        let error = try #require(throws: (any Error).self) {
            try OutputExtractor.extract(stdout: stdout, declarations: declarations)
        }
        
        #expect(error is OutputResolutionError, "A mismatched-type default is fail-loud, not a silent pass")
    }
    
    @Test("A null default remains an absence marker")
    func nullDefaultStaysAbsenceMarker() throws {
        // Given
        let stdout = #"{"a":1}"#
        let declarations = ["b": OutputSpec(extractor: .path("$.b"), type: .int, default: .null)]

        // When
        let output = try OutputExtractor.extract(stdout: stdout, declarations: declarations)

        // Then
        let object = try #require(output.objectValue)
        
        #expect(object["b"] == .null, "The .null absence marker is exempt from coercion")
    }
    
    @Test("Throws when a required item is missing")
    func requiredMissingThrows() throws {
        // Given
        let stdout = #"{"a":1}"#
        let declarations = ["b": OutputSpec(extractor: .path("$.b"))]

        // Then
        let error = try #require(throws: (any Error).self) {
            try OutputExtractor.extract(stdout: stdout, declarations: declarations)
        }
        
        #expect(error is OutputResolutionError, "expected OutputResolutionError, got \(error)")
    }
    
    // MARK: - type coercion
    @Test("Coerces a string to an integer")
    func coerceIntFromString() throws {
        // Given
        let stdout = "42\n"
        let declarations = ["n": OutputSpec(extractor: .line(0), type: .int)]

        // When
        let output = try OutputExtractor.extract(stdout: stdout, declarations: declarations)

        // Then
        let object = try #require(output.objectValue)
        
        #expect(object["n"] == .int(42))
    }
    
    @Test("Boolean coercion")
    func coerceBool() throws {
        // Given
        let stdout = "true\n"
        let declarations = ["b": OutputSpec(extractor: .line(0), type: .bool)]

        // When
        let output = try OutputExtractor.extract(stdout: stdout, declarations: declarations)

        // Then
        let object = try #require(output.objectValue)
        
        #expect(object["b"] == .bool(true))
    }
    
    @Test("Throws when coercion fails")
    func coerceFailureThrows() throws {
        // Given
        let stdout = "not-a-number"
        let declarations = ["n": OutputSpec(extractor: .line(0), type: .int)]

        // Then
        let error = try #require(throws: (any Error).self) {
            try OutputExtractor.extract(stdout: stdout, declarations: declarations)
        }
        
        #expect(error is OutputResolutionError)
    }
    
    @Test("A double beyond integer range is not accepted as an int")
    func coerceIntRejectsOutOfRangeIntegralDouble() throws {
        // Given
        let stdout = #"{"n":1e20}"#
        let declarations = ["n": OutputSpec(extractor: .path("$.n"), type: .int)]

        // Then
        let error = try #require(throws: (any Error).self, "An out-of-range integral double should be rejected fail-loud instead of trapping") {
            try OutputExtractor.extract(stdout: stdout, declarations: declarations)
        }
        
        #expect(error is OutputResolutionError, "got \(error)")
    }
    
    @Test("A finite float string is coerced to a float")
    func coerceFloatFromStringFinite() throws {
        // Given
        let declarations = ["f": OutputSpec(extractor: .line(0), type: .float)]

        // When
        let output = try OutputExtractor.extract(stdout: "3.14\n", declarations: declarations)

        // Then
        let object = try #require(output.objectValue)
        
        #expect(object["f"] == .double(3.14))
    }
    
    @Test("Infinity and NaN are rejected")
    func coerceFloatRejectsNonFinite() throws {
        // Given
        for token in ["inf", "Inf", "infinity", "-inf", "nan", "NaN", "1e999"] {
            let declarations = ["f": OutputSpec(extractor: .line(0), type: .float)]

        // Then
            let error = try #require(throws: (any Error).self, "non-finite '\(token)' must fail-loud") {
                try OutputExtractor.extract(stdout: "\(token)\n", declarations: declarations)
            }
            
            #expect(error is OutputResolutionError, "got \(error)")
            #expect("\(error)".contains("non-finite"), "The message should carry the reason: \(error)")
        }
    }
    
    @Test("A non-finite path result is rejected")
    func jSONPathNonFiniteRejected() throws {
        // Given
        for type in [OutputSpec.CoerceType.float, .json] {
            let declarations = ["v": OutputSpec(extractor: .path("$.v"), type: type)]

        // Then
            let error = try #require(throws: (any Error).self, "jsonpath non-finite (type=\(type)) must fail-loud") {
                try OutputExtractor.extract(stdout: #"{"v":-1e999}"#, declarations: declarations)
            }
            
            #expect(error is OutputResolutionError, "got \(error)")
            #expect("\(error)".contains("non-finite"), "Reason stated explicitly: \(error)")
        }
    }
    
    @Test("The json type preserves structure as-is")
    func jsonTypePreservesStructure() throws {
        // Given
        let stdout = #"{"arr":[1,2,3]}"#
        let declarations = ["a": OutputSpec(extractor: .path("$.arr"), type: .json)]

        // When
        let output = try OutputExtractor.extract(stdout: stdout, declarations: declarations)

        // Then
        let object = try #require(output.objectValue)
        
        #expect(object["a"] == .array([.int(1), .int(2), .int(3)]))
    }
    
    // MARK: - failure modes
    @Test("Throws when input is not JSON")
    func invalidJSONThrows() throws {
        let stdout = "not json {"
        let declarations = ["x": OutputSpec(extractor: .path("$.x"))]
        let error = try #require(throws: (any Error).self) {
            try OutputExtractor.extract(stdout: stdout, declarations: declarations)
        }
        
        #expect(error is OutputResolutionError)
    }
    
    @Test("The reserved _raw key cannot be used in declarations")
    func reservedRawKeyRejected() throws {
        let stdout = "{}"
        let declarations = ["_raw": OutputSpec(extractor: .path("$"))]
        let error = try #require(throws: (any Error).self) {
            try OutputExtractor.extract(stdout: stdout, declarations: declarations)
        }
        
        guard let resolutionError = error as? OutputResolutionError else {
            Issue.record()
            
            return
        }
        
        #expect(resolutionError.message.contains("_raw"))
    }
    
    // MARK: - Codable round-trip
    @Test("Short-form decoding")
    func codableShortFormDecode() throws {
        let json = #""$.foo.bar""#
        let dec = JSONDecoder()
        let spec = try dec.decode(OutputSpec.self, from: json.data(using: .utf8)!)
        guard case .path(let path) = spec.extractor else {
            Issue.record()
            
            return
        }
        
        #expect(path == "$.foo.bar")
        #expect(spec.type == .string)
        #expect(!spec.canOmit)
    }
    
    @Test("Full-form decoding")
    func codableFullFormDecode() throws {
        let json = #"{"path":"$.x","type":"int","default":99,"hint":"count"}"#
        let dec = JSONDecoder()
        let spec = try dec.decode(OutputSpec.self, from: json.data(using: .utf8)!)
        guard case .path(let path) = spec.extractor else {
            Issue.record()
            
            return
        }
        
        #expect(path == "$.x")
        #expect(spec.type == .int)
        #expect(spec.canOmit)
        #expect(spec.default == .int(99))
        #expect(spec.hint == "count")
    }
    
    @Test("Writing a default means the field is omittable")
    func codableDefaultImpliesOmittable() throws {
        let json = #"{"path":"$.x","type":"int","default":99}"#
        let dec = JSONDecoder()
        let spec = try dec.decode(OutputSpec.self, from: json.data(using: .utf8)!)
        #expect(spec.canOmit)
        #expect(spec.default == .int(99))
    }
    
    @Test("Regex and line extractor decoding")
    func codableRegexLineDecode() throws {
        let dec = JSONDecoder()
        let result = try dec.decode(OutputSpec.self,
            from: #"{"regex":"^x=(\\d+)$","type":"int"}"#.data(using: .utf8)!)
        guard case .regex(let path) = result.extractor else {
            Issue.record()
            
            return
        }
        
        #expect(path == #"^x=(\d+)$"#)
        let decoded = try dec.decode(OutputSpec.self,
            from: #"{"line":-1}"#.data(using: .utf8)!)
        guard case .line(let lineNumber) = decoded.extractor else {
            Issue.record()
            
            return
        }
        
        #expect(lineNumber == -1)
    }
    
    @Test("Declaring more than one extractor is rejected")
    func codableMultipleExtractorsRejected() throws {
        let json = #"{"path":"$.a","regex":"x"}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(OutputSpec.self,
                from: json.data(using: .utf8)!) }
    }
    
    @Test("Short-form round trip")
    func codableShortFormRoundTrip() throws {
        let spec = OutputSpec(extractor: .path("$.x"))
        let encoder = try JSONEncoder().encode(spec)
        #expect(String(data: encoder, encoding: .utf8) == "\"$.x\"")
    }
    
    // MARK: - semantic corner cases
    @Test("An explicit null is treated as absence")
    func explicitNullTreatedAsMissing() throws {
        let stdout = #"{"a":null}"#
        let declarations = ["a": OutputSpec(extractor: .path("$.a"))]
        let error = try #require(throws: (any Error).self) {
            try OutputExtractor.extract(stdout: stdout, declarations: declarations)
        }
        
        #expect(error is OutputResolutionError, "explicit null without a default should fail — this field has no default")
    }
    
    @Test("An explicit null stays null even with a default")
    func explicitNullWithDefaultReturnsNull() throws {
        let stdout = #"{"a":null}"#
        let declarations = ["a": OutputSpec(extractor: .path("$.a"), default: .null)]
        let output = try OutputExtractor.extract(stdout: stdout, declarations: declarations)
        let object = try #require(output.objectValue)
        
        #expect(object["a"] == .null)
    }
    
    @Test("Uses the whole match when there is no capture group")
    func regexNoCaptureGroupUsesWholeMatch() throws {
        let stdout = "hello world"
        let declarations = ["w": OutputSpec(extractor: .regex(#"\bworld\b"#))]
        let output = try OutputExtractor.extract(stdout: stdout, declarations: declarations)
        let object = try #require(output.objectValue)
        
        #expect(object["w"] == .string("world"))
    }
    
    @Test("stdout ending with CRLF is also split into lines")
    func lineExtractorSplitsCRLF() throws {
        // Given
        let stdout = "first\r\nsecond\r\nthird\r\n"
        let declarations = ["mid": OutputSpec(extractor: .line(1))]

        // When
        let output = try OutputExtractor.extract(stdout: stdout, declarations: declarations)

        // Then
        let object = try #require(output.objectValue)
        #expect(object["mid"] == .string("second"))
    }


    // MARK: - Private
}
