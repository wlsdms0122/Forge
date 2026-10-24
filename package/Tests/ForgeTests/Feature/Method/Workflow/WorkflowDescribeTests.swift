//
//  WorkflowDescribeTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("WorkflowDescribe Tests")
struct WorkflowDescribeTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("describe")

    // MARK: - Initializer
    // MARK: - Test
    @Test("Returns the declared inputs and the return type")
    func returnsInputsAndOutputsSchema() async throws {
        // Given
        let (method, authority, directory) = try await makeMethod("schema")
        defer { try? FileManager.default.removeItem(at: directory) }
        try workflowFile(#"""
        parameters: [ msg: String, tag: String? ]
        failing: [nonzero_exit, timeout]
        body:
          - let: x
            value: { call: { procedure: shell, arguments: { command: ["/bin/echo", { ref: msg }] } } }
        returns: "Dictionary<String, Any>"
        result: { dictionary: [ [v, { ref: x }] ] }
        """#, named: "echo").write(to: directory.appendingPathComponent("echo.yaml"),
            atomically: true, encoding: .utf8)
        let token = authority.mint(TokenClaims(principal: "system:admin"))

        // When
        let result = try await method.handle(request(["token": .string(token), "name": "echo"]))

        // Then
        #expect(result["name"]?.stringValue == "echo")
        #expect(result["source"]?.stringValue == "echo.yaml")
        let inputs = result["inputs"]?.objectValue ?? [:]
        let message = inputs["msg"]?.objectValue ?? [:]
        #expect(message["type"]?.stringValue == "String")
        #expect(!message.keys.contains("default"))
        let tag = inputs["tag"]?.objectValue ?? [:]
        #expect(tag["type"]?.stringValue == "String?")
        #expect(!tag.keys.contains("default"), "an input whose file writes no default reports none")
        #expect(result["returns"]?.stringValue == "Dictionary<String, Any>")
    }
    
    @Test("Describe and list answer the description and each input's hint the file writes beside them")
    func answersTheProseBesideTheDeclaration() async throws {
        // Given
        let (method, authority, directory) = try await makeMethod("prose")
        defer { try? FileManager.default.removeItem(at: directory) }
        try workflowFile(#"""
        description: Says hello.
        parameters: [ who: { type: String, hint: whom to greet }, loud: { type: Bool, default: false } ]
        returns: String
        result: { format: "hello, ${who}", with: { who: { ref: who } } }
        """#, named: "greet").write(to: directory.appendingPathComponent("greet.yaml"),
            atomically: true, encoding: .utf8)
        let token = authority.mint(TokenClaims(principal: "system:admin"))
        let list = WorkflowListMethod(store: method.store)

        // When
        let described = try await method.handle(request(["token": .string(token), "name": "greet"]))
        let listed = try await list.handle(RPCRequest(id: "r-list", method: "workflow.list", params: ["token": .string(token)]))

        // Then
        #expect(described["description"]?.stringValue == "Says hello.")
        let inputs = described["inputs"]?.objectValue ?? [:]
        #expect((inputs["who"]?.objectValue)?["hint"]?.stringValue == "whom to greet")
        #expect((inputs["loud"]?.objectValue)?["hint"] == nil)
        #expect((inputs["loud"]?.objectValue)?["default"]?.boolValue == false, "the default the file writes")
        let workflows = listed["workflows"]?.arrayValue ?? []
        #expect(workflows.first?["description"]?.stringValue == "Says hello.")
    }

    @Test("A workflow with no parameters answers empty inputs and returns Null")
    func emptyInputsAndOutputsAreEmptyObjects() async throws {
        // Given
        let (method, authority, directory) = try await makeMethod("empty")
        defer { try? FileManager.default.removeItem(at: directory) }
        try workflowFile(#"""
        failing: [nonzero_exit, timeout]
        body:
          - let: x
            value: { call: { procedure: shell, arguments: { command: ["/bin/true"] } } }
        """#, named: "noop").write(to: directory.appendingPathComponent("noop.yaml"),
            atomically: true, encoding: .utf8)
        let token = authority.mint(TokenClaims(principal: "system:admin"))

        // When
        let result = try await method.handle(request(["token": .string(token), "name": "noop"]))

        // Then
        #expect((result["inputs"]?.objectValue)?.isEmpty == true)
        #expect(result["returns"]?.stringValue == "Null")
    }
    
    @Test("Throws when the name parameter is missing")
    func missingNameParamThrows() async throws {
        // Given
        let (method, authority, directory) = try await makeMethod("missing-name")
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = authority.mint(TokenClaims(principal: "system:admin"))
        do {

        // When
            _ = try await method.handle(request(["token": .string(token)]))

        // Then
            Issue.record("expected ProtocolError")
        } catch let error as ProtocolError {
            #expect(error.message.contains("name"), Comment(rawValue: error.message))
        }
    }
    
    @Test("Throws for an unknown workflow")
    func unknownWorkflowThrows() async throws {
        // Given
        let (method, authority, directory) = try await makeMethod("unknown")
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = authority.mint(TokenClaims(principal: "system:admin"))
        do {

        // When
            _ = try await method.handle(request(["token": .string(token), "name": "nope"]))

        // Then
            Issue.record("expected WorkflowNotFound")
        } catch let error as WorkflowNotFound {
            #expect(error.message.contains("nope"), Comment(rawValue: error.message))
        }
    }
    
    // MARK: - Private
    
    private func makeMethod(_ test: String) async throws
    
    -> (WorkflowDescribeMethod, TokenAuthority, URL) {
        let directory = try temporary.make(test)
        let store = try WorkflowCatalog(directory: directory)
        let authority = TokenAuthority()
        
        return (WorkflowDescribeMethod(store: store), authority, directory)
    }
    
    private func request(_ params: [String: JSONValue]) -> RPCRequest {
        RPCRequest(id: "r-\(UUID().uuidString.prefix(6))",
            method: "workflow.describe", params: params)
    }
}
