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
        #expect(try JSONPath("$").tokens == [])
        #expect(try JSONPath("$.x").tokens == [.field("x")])
        #expect(try JSONPath("$.a.b.c").tokens == [.field("a"), .field("b"), .field("c")])
        #expect(try JSONPath("$.arr[0]").tokens == [.field("arr"), .index(0)])
        #expect(try JSONPath("$.arr[-1]").tokens == [.field("arr"), .index(-1)])
        #expect(try JSONPath("$.arr[*]").tokens == [.field("arr"), .wildcardIndex])
        #expect(try JSONPath("$.obj.*").tokens == [.field("obj"), .wildcardField])
    }
    
    @Test("Rejects paths with invalid syntax")
    func tokenizeRejectsBadSyntax() {
        #expect(throws: (any Error).self) { try JSONPath("").tokens }
        #expect(throws: (any Error).self) { try JSONPath(".x").tokens }
        #expect(throws: (any Error).self) { try JSONPath("$.").tokens }
        #expect(throws: (any Error).self) { try JSONPath("$.x[").tokens }
        #expect(throws: (any Error).self) { try JSONPath("$.x[1:5]").tokens }
        #expect(throws: (any Error).self) { try JSONPath("$.x[?(@.y>1)]").tokens }
        #expect(throws: (any Error).self) { try JSONPath("$..x").tokens }
    }
    
    // MARK: - Evaluate
    @Test("The root path refers to the whole value")
    func evaluateRoot() throws {
        // Given
        let value = json(#"{"a":1}"#)

        // Then
        #expect(try JSONPath("$").evaluate(on: value) == value)
    }
    
    @Test("Field access")
    func evaluateField() throws {
        // Given
        let value = json(#"{"name":"hello"}"#)

        // Then
        #expect(try JSONPath("$.name").evaluate(on: value) == .string("hello"))
    }
    
    @Test("Nested field access")
    func evaluateNestedField() throws {
        // Given
        let value = json(#"{"a":{"b":{"c":42}}}"#)

        // Then
        #expect(try JSONPath("$.a.b.c").evaluate(on: value) == .int(42))
    }
    
    @Test("Array index access")
    func evaluateArrayIndex() throws {
        // Given
        let value = json(#"{"arr":["x","y","z"]}"#)

        // Then
        #expect(try JSONPath("$.arr[0]").evaluate(on: value) == .string("x"))
        #expect(try JSONPath("$.arr[2]").evaluate(on: value) == .string("z"))
        #expect(try JSONPath("$.arr[-1]").evaluate(on: value) == .string("z"))
        #expect(try JSONPath("$.arr[-3]").evaluate(on: value) == .string("x"))
    }
    
    @Test("An out-of-bounds index throws")
    func evaluateOutOfBoundsThrows() {
        // Given
        let value = json(#"{"arr":["a"]}"#)

        // Then
        #expect(throws: (any Error).self) { try JSONPath("$.arr[5]").evaluate(on: value) }
        #expect(throws: (any Error).self) { try JSONPath("$.arr[-5]").evaluate(on: value) }
    }
    
    @Test("Index wildcard")
    func evaluateWildcardIndex() throws {
        // Given
        let value = json(#"{"arr":[1,2,3]}"#)

        // Then
        #expect(try JSONPath("$.arr[*]").evaluate(on: value) == .array([.int(1), .int(2), .int(3)]))
    }
    
    @Test("Field wildcard")
    func evaluateWildcardField() throws {
        // Given
        let value = json(#"{"obj":{"a":1,"b":2}}"#)

        // Then
        #expect(try JSONPath("$.obj.*").evaluate(on: value) == .array([.int(1), .int(2)]))
    }
    
    @Test("A missing path throws notFound")
    func evaluateMissingThrowsNotFound() throws {
        // Given
        let value = json(#"{"a":1}"#)

        // Then
        let error = try #require(throws: (any Error).self) { try JSONPath("$.b").evaluate(on: value) }
        
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
        #expect(throws: (any Error).self) { try JSONPath("$.a.b").evaluate(on: value) }
        #expect(throws: (any Error).self) { try JSONPath("$.a[0]").evaluate(on: value) }
    }
    
    @Test("Chaining wildcards is a syntax error")
    func evaluateWildcardChainingIsSyntaxError() throws {
        // Given
        let value = json(#"{"arr":[{"name":"a"},{"name":"b"}]}"#)

        // Then
        let error = try #require(throws: (any Error).self) { try JSONPath("$.arr[*].name").evaluate(on: value) }
        
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
        #expect(try JSONPath("$[0]").evaluate(on: value) == .int(1))
        #expect(try JSONPath("$[-1]").evaluate(on: value) == .int(3))
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
