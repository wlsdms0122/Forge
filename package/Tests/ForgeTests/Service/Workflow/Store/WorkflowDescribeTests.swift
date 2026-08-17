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
    @Test("Returns the declared input and output schema")
    func returnsInputsAndOutputsSchema() async throws {
        // Given
        let (method, authority, directory) = try await makeMethod("schema")
        defer { try? FileManager.default.removeItem(at: directory) }
        try workflowFile(#"""
        name: echo
        description: test wf
        parameters:
          msg:
            type: string
            hint: message body
          tag:
            type: string
            default: null
        body:
          - id: x
            shell:
              command: ["/bin/echo", { ref: msg }]
        result:
          v: { ref: x }
        """#, named: "echo").write(to: directory.appendingPathComponent("echo.yaml"),
            atomically: true, encoding: .utf8)
        let token = authority.mint(TokenClaims(principal: "system:admin"))

        // When
        let result = try await method.handle(request(["token": token, "name": "echo"]))

        // Then
        #expect(result.dict["name"] as? String == "echo")
        #expect(result.dict["description"] as? String == "test wf")
        #expect(result.dict["source"] as? String == "echo.yaml")
        let inputs = result.dict["inputs"] as? [String: Any] ?? [:]
        let message = inputs["msg"] as? [String: Any] ?? [:]
        #expect(message["type"] as? String == "string")
        #expect(message["hint"] as? String == "message body")
        let tag = inputs["tag"] as? [String: Any] ?? [:]
        #expect(tag.keys.contains("default"), "declaring default (even as null) makes this input optional")
        let outputs = result.dict["outputs"] as? [String: Any] ?? [:]
        let vForm = outputs["v"] as? [String: Any] ?? [:]
        #expect(vForm["ref"] as? String == "x")
    }
    
    @Test("Absent schemas answer as empty objects, not null")
    func emptyInputsAndOutputsAreEmptyObjects() async throws {
        // Given
        let (method, authority, directory) = try await makeMethod("empty")
        defer { try? FileManager.default.removeItem(at: directory) }
        try workflowFile(#"""
        name: noop
        body:
          - id: x
            shell:
              command: ["/bin/true"]
        """#, named: "noop").write(to: directory.appendingPathComponent("noop.yaml"),
            atomically: true, encoding: .utf8)
        let token = authority.mint(TokenClaims(principal: "system:admin"))

        // When
        let result = try await method.handle(request(["token": token, "name": "noop"]))

        // Then
        #expect((result.dict["inputs"]  as? [String: Any])?.isEmpty == true)
        #expect((result.dict["outputs"] as? [String: Any])?.isEmpty == true)
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
        let store = SpecCatalog(directory: directory, loader: ForgeSpec.loader())
        let authority = TokenAuthority()
        
        return (WorkflowDescribeMethod(store: store, tokenAuthority: authority), authority, directory)
    }
    
    private func request(_ params: [String: Any]) -> RPCRequest {
        RPCRequest(id: "r-\(UUID().uuidString.prefix(6))",
            method: "workflow.describe", params: params)
    }
}
