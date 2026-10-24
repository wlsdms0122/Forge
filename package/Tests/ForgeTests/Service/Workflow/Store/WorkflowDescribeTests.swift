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
        let result = try await method.handle(request(["token": token, "name": "echo"]))

        // Then
        #expect(result.dict["name"] as? String == "echo")
        #expect(result.dict["source"] as? String == "echo.yaml")
        let inputs = result.dict["inputs"] as? [String: Any] ?? [:]
        let message = inputs["msg"] as? [String: Any] ?? [:]
        #expect(message["type"] as? String == "String")
        #expect(!message.keys.contains("default"))
        let tag = inputs["tag"] as? [String: Any] ?? [:]
        #expect(tag["type"] as? String == "String?")
        #expect(!tag.keys.contains("default"), "an input whose file writes no default reports none")
        #expect(result.dict["returns"] as? String == "Dictionary<String, Any>")
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
        let list = WorkflowListMethod(store: method.store, tokenAuthority: authority)

        // When
        let described = try await method.handle(request(["token": token, "name": "greet"]))
        let listed = try await list.handle(RPCRequest(id: "r-list", method: "workflow.list", params: ["token": token]))

        // Then
        #expect(described.dict["description"] as? String == "Says hello.")
        let inputs = described.dict["inputs"] as? [String: Any] ?? [:]
        #expect((inputs["who"] as? [String: Any])?["hint"] as? String == "whom to greet")
        #expect((inputs["loud"] as? [String: Any])?["hint"] == nil)
        #expect((inputs["loud"] as? [String: Any])?["default"] as? Bool == false, "the default the file writes")
        let workflows = listed.dict["workflows"] as? [[String: Any]] ?? []
        #expect(workflows.first?["description"] as? String == "Says hello.")
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
        let result = try await method.handle(request(["token": token, "name": "noop"]))

        // Then
        #expect((result.dict["inputs"]  as? [String: Any])?.isEmpty == true)
        #expect(result.dict["returns"] as? String == "Null")
    }
    
    @Test("Throws when the name parameter is missing")
    func missingNameParamThrows() async throws {
        // Given
        let (method, authority, directory) = try await makeMethod("missing-name")
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = authority.mint(TokenClaims(principal: "system:admin"))
        do {

        // When
            _ = try await method.handle(request(["token": token]))

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
            _ = try await method.handle(request(["token": token, "name": "nope"]))

        // Then
            Issue.record("expected ResolutionError")
        } catch let error as ResolutionError {
            #expect(error.message.contains("nope"), Comment(rawValue: error.message))
        }
    }
    
    // MARK: - Private
    
    private func makeMethod(_ test: String) async throws
    
    -> (WorkflowDescribeMethod, TokenAuthority, URL) {
        let directory = try temporary.make(test)
        let store = SpecCatalog(directory: directory)
        let authority = TokenAuthority()
        
        return (WorkflowDescribeMethod(store: store, tokenAuthority: authority), authority, directory)
    }
    
    private func request(_ params: [String: Any]) -> RPCRequest {
        RPCRequest(id: "r-\(UUID().uuidString.prefix(6))",
            method: "workflow.describe", params: params)
    }
}
