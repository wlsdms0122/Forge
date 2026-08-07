//
//  JSONPathTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("JSONPath Tests")
struct JSONPathTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    // MARK: - Tokenize
    @Test("Splits a path into tokens")
    func tokenizeBasic() throws {
        #expect(try JSONPath.tokenize("$") == [])
        #expect(try JSONPath.tokenize("$.x") == [.field("x")])
        #expect(try JSONPath.tokenize("$.a.b.c") == [.field("a"), .field("b"), .field("c")])
        #expect(try JSONPath.tokenize("$.arr[0]") == [.field("arr"), .index(0)])
        #expect(try JSONPath.tokenize("$.arr[-1]") == [.field("arr"), .index(-1)])
        #expect(try JSONPath.tokenize("$.arr[*]") == [.field("arr"), .wildcardIndex])
        #expect(try JSONPath.tokenize("$.obj.*") == [.field("obj"), .wildcardField])
    }
    
    @Test("Rejects paths with invalid syntax")
    func tokenizeRejectsBadSyntax() {
        #expect(throws: (any Error).self) { try JSONPath.tokenize("") }
        #expect(throws: (any Error).self) { try JSONPath.tokenize(".x") }
        #expect(throws: (any Error).self) { try JSONPath.tokenize("$.") }
        #expect(throws: (any Error).self) { try JSONPath.tokenize("$.x[") }
        #expect(throws: (any Error).self) { try JSONPath.tokenize("$.x[1:5]") }
        #expect(throws: (any Error).self) { try JSONPath.tokenize("$.x[?(@.y>1)]") }
        #expect(throws: (any Error).self) { try JSONPath.tokenize("$..x") }
    }
    
    // MARK: - Evaluate
    @Test("The root path refers to the whole value")
    func evaluateRoot() throws {
        // Given
        let value = json(#"{"a":1}"#)

        // Then
        #expect(try JSONPath.evaluate("$", on: value) == value)
    }
    
    @Test("Field access")
    func evaluateField() throws {
        // Given
        let value = json(#"{"name":"hello"}"#)

        // Then
        #expect(try JSONPath.evaluate("$.name", on: value) == .string("hello"))
    }
    
    @Test("Nested field access")
    func evaluateNestedField() throws {
        // Given
        let value = json(#"{"a":{"b":{"c":42}}}"#)

        // Then
        #expect(try JSONPath.evaluate("$.a.b.c", on: value) == .int(42))
    }
    
    @Test("Array index access")
    func evaluateArrayIndex() throws {
        // Given
        let value = json(#"{"arr":["x","y","z"]}"#)

        // Then
        #expect(try JSONPath.evaluate("$.arr[0]", on: value) == .string("x"))
        #expect(try JSONPath.evaluate("$.arr[2]", on: value) == .string("z"))
        #expect(try JSONPath.evaluate("$.arr[-1]", on: value) == .string("z"))
        #expect(try JSONPath.evaluate("$.arr[-3]", on: value) == .string("x"))
    }
    
    @Test("An out-of-bounds index throws")
    func evaluateOutOfBoundsThrows() {
        // Given
        let value = json(#"{"arr":["a"]}"#)

        // Then
        #expect(throws: (any Error).self) { try JSONPath.evaluate("$.arr[5]", on: value) }
        #expect(throws: (any Error).self) { try JSONPath.evaluate("$.arr[-5]", on: value) }
    }
    
    @Test("Index wildcard")
    func evaluateWildcardIndex() throws {
        // Given
        let value = json(#"{"arr":[1,2,3]}"#)

        // Then
        #expect(try JSONPath.evaluate("$.arr[*]", on: value) == .array([.int(1), .int(2), .int(3)]))
    }
    
    @Test("Field wildcard")
    func evaluateWildcardField() throws {
        // Given
        let value = json(#"{"obj":{"a":1,"b":2}}"#)

        // Then
        #expect(try JSONPath.evaluate("$.obj.*", on: value) == .array([.int(1), .int(2)]))
    }
    
    @Test("A missing path throws notFound")
    func evaluateMissingThrowsNotFound() throws {
        // Given
        let value = json(#"{"a":1}"#)

        // Then
        let error = try #require(throws: (any Error).self) { try JSONPath.evaluate("$.b", on: value) }
        
        guard case JSONPath.EvalError.notFound = error else {
            Issue.record("expected notFound, got \(error)")
            
            return
        }
    }
    
    @Test("Throws on a type mismatch")
    func evaluateTypeMismatchThrows() {
        // Given
        let value = json(#"{"a":"string"}"#)

        // Then
        #expect(throws: (any Error).self) { try JSONPath.evaluate("$.a.b", on: value) }
        #expect(throws: (any Error).self) { try JSONPath.evaluate("$.a[0]", on: value) }
    }
    
    @Test("Chaining wildcards is a syntax error")
    func evaluateWildcardChainingIsSyntaxError() throws {
        // Given
        let value = json(#"{"arr":[{"name":"a"},{"name":"b"}]}"#)

        // Then
        let error = try #require(throws: (any Error).self) { try JSONPath.evaluate("$.arr[*].name", on: value) }
        
        guard case JSONPath.EvalError.syntax = error else {
            Issue.record("expected syntax, got \(error)")
            
            return
        }
    }
    
    @Test("Index access when the top level is an array")
    func evaluateTopLevelArrayIndex() throws {
        // Given
        let value = json(#"[1,2,3]"#)

        // Then
        #expect(try JSONPath.evaluate("$[0]", on: value) == .int(1))
        #expect(try JSONPath.evaluate("$[-1]", on: value) == .int(3))
    }
    
    // MARK: - Private
    private func json(_ s: String) -> JSONValue {
        let data = s.data(using: .utf8)!
        let any = try! JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        
        return convert(any)
    }
    
    private func convert(_ any: Any) -> JSONValue {
        if any is NSNull { return .null }
        if let boolean = any as? Bool, CFGetTypeID(any as CFTypeRef) == CFBooleanGetTypeID() { return .bool(boolean) }
        if let integer = any as? Int { return .int(integer) }
        if let double = any as? Double { return .double(double) }
        if let string = any as? String { return .string(string) }
        if let array = any as? [Any] { return .array(array.map(convert)) }
        if let dict = any as? [String: Any] {
            var object: [String: JSONValue] = [:]
            for (k, value) in dict { object[k] = convert(value) }
            
            return .object(object)
        }
        
        return .null
    }
}
