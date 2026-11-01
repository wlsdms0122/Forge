//
//  WorkflowDispatchTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("WorkflowDispatch Tests")
struct WorkflowDispatchTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("dispatch")

    private var anonSpec: [String: JSONValue] {
        [
            "failing": ["nonzero_exit", "timeout"],
            "body": [
                ["let": "x", "value": ["call": ["procedure": "shell", "arguments": ["command": ["/bin/echo", "ok"]]]]],
            ],
            "returns": "Dictionary<String, Any>",
            "result": ["dictionary": [["v", ["ref": "x"]]]],
        ]
    }

    // MARK: - Initializer
    // MARK: - Test
    // MARK: - inline spec
    @Test("An inline spec runs anonymously without a name")
    func inlineSpecRunsAnonymously() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["cli:test": ["<inline>"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))

        // When
        let result = try await method.handle(request(["token": .string(token), "spec": .object(anonSpec)]), claims: try #require(authority.verify(token)))

        // Then
        #expect(result["status"]?.stringValue == "ok")
        #expect(result["path"]?.stringValue == Workflow.inlineSigil, "The result path of an inline run is fixed to the sigil")
    }

    @Test("Run id is freshly minted — the wire id is not borrowed")
    func runIDMintedNotBorrowedFromWireID() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["*": ["*"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))
        let wireID = "fc-client-collide"
        let first = try await method.handle(RPCRequest(id: wireID, method: "workflow.dispatch",
                params: ["token": .string(token), "spec": .object(anonSpec)]), claims: try #require(authority.verify(token)))

        // Then
        let firstID = try #require(first["run_id"]?.stringValue)
        #expect(firstID.hasPrefix("wf-"), "runID should be forge-minted (wf-*) — borrowing the wire id is forbidden (finding J): \(firstID)")
        #expect(firstID != wireID, "runID must not equal the client wire id")
        let second = try await method.handle(RPCRequest(id: wireID, method: "workflow.dispatch",
                params: ["token": .string(token), "spec": .object(anonSpec)]), claims: try #require(authority.verify(token)))
        let secondID = try #require(second["run_id"]?.stringValue)
        #expect(firstID != secondID, "Two dispatches with the same wire id sharing a runID means cross-run contamination (finding J)")
    }

    @Test("A path beside an inline spec is rejected")
    func pathBesideInlineSpecRejected() async throws {
        // Given
        let (sut, authority, _) = try await makeMethod(policy: ["*": ["*"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))
        let claims = try #require(authority.verify(token))

        // When
        let error = try await #require(throws: ProtocolError.self) {
            try await sut.handle(
                request(["token": .string(token), "path": "echo.yaml", "spec": .object(anonSpec)]),
                claims: claims
            )
        }

        // Then
        #expect(error.message == "workflow.dispatch: 'path' and 'spec' are mutually exclusive; pass only one")
    }

    @Test(
        "A path or spec of the wrong type is refused, not read as absent",
        arguments: [
            (["path": "echo.yaml", "spec": "oops"], "workflow.dispatch: 'path' and 'spec' are mutually exclusive; pass only one"),
            (["spec": "oops"], "workflow.dispatch: 'spec' is an object"),
            (["path": 5], "workflow.dispatch: 'path' is a non-empty string"),
            (["path": ""], "workflow.dispatch: 'path' is a non-empty string")
        ] as [([String: JSONValue], String)]
    )
    func wronglyTypedProgramRefused(program: [String: JSONValue], message: String) async throws {
        // Given
        let (sut, authority, _) = try await makeMethod(policy: ["*": ["*"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))
        let claims = try #require(authority.verify(token))
        let params = program.merging(["token": .string(token)]) { first, _ in first }

        // When
        let error = try await #require(throws: ProtocolError.self) {
            try await sut.handle(request(params), claims: claims)
        }

        // Then
        #expect(error.message == message)
    }

    @Test("An inline spec is rejected without the sigil policy")
    func inlineSpecDeniedWithoutSigilPolicy() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["cli:test": ["echo"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))
        do {

        // When
            _ = try await method.handle(request(["token": .string(token), "spec": .object(anonSpec)]), claims: try #require(authority.verify(token)))

        // Then
            Issue.record("Should be rejected without an <inline> policy")
        } catch let error as PolicyDenied {
            #expect(error.message.contains(Workflow.inlineSigil), "The denial reason should include the sigil: \(error.message)")
        }
    }

    @Test("A wildcard policy also allows inline")
    func wildcardPolicyAllowsInline() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["*": ["*"]])
        let token = authority.mint(TokenClaims(principal: "cli:anything"))

        // When
        let result = try await method.handle(request(["token": .string(token), "spec": .object(anonSpec)]), claims: try #require(authority.verify(token)))

        // Then
        #expect(result["status"]?.stringValue == "ok")
    }

    @Test("A malformed spec answers with a readable error")
    func malformedSpecGivesFriendlyError() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["*": ["*"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))
        let badSpec: [String: JSONValue] = [
            "body": [["shell": ["command": ["echo", "hi"]]]],
        ]
        do {

        // When
            _ = try await method.handle(request(["token": .string(token), "spec": .object(badSpec)]), claims: try #require(authority.verify(token)))

        // Then
            Issue.record("A malformed spec should be rejected")
        } catch let error as ProtocolError {
            #expect(error.message.contains("body[0]"), "JSON path notation: \(error.message)")
            #expect(error.message.contains("shell"), "Unknown key named explicitly: \(error.message)")
            #expect(!error.message.contains("CodingKeys"), "Raw Swift errors must not leak: \(error.message)")
        }
    }

    @Test("A refused inline spec gives the refusal's message as its reason")
    func refusedSpecGivesTheRefusalMessage() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["*": ["*"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))
        let badSpec: [String: JSONValue] = [
            "body": [["let": "x", "value": ["format": 5]]],
        ]
        let refusal = await #expect(throws: WorkflowValidationError.self) {
            try await WorkflowReader(directory: nil).inline(badSpec)
        }

        // When
        let error = await #expect(throws: ProtocolError.self) {
            try await method.handle(request(["token": .string(token), "spec": .object(badSpec)]), claims: try #require(authority.verify(token)))
        }

        // Then
        #expect(error?.message == "workflow.dispatch: malformed 'spec': \(try #require(refusal).message)")
    }

    @Test("An inline spec containing an invalid reference is rejected")
    func inlineSpecWithInvalidRefRejected() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["*": ["*"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))
        let badSpec: [String: JSONValue] = [
            "failing": ["nonzero_exit", "timeout"],
            "body": [
                ["let": "a", "value": ["call": ["procedure": "shell", "arguments": ["command": ["/bin/echo", ["ref": "nonexistent"]]]]]],
            ],
        ]
        do {

        // When
            _ = try await method.handle(request(["token": .string(token), "spec": .object(badSpec)]), claims: try #require(authority.verify(token)))

        // Then
            Issue.record("A spec containing an undeclared ref should be rejected at dispatch")
        } catch let error as ProtocolError {
            #expect(error.message.contains("malformed 'spec'"), "Validation failure message: \(error.message)")
            #expect(error.message.contains("nonexistent"), "Undeclared ref named explicitly: \(error.message)")
        }
    }

    // MARK: - path
    @Test("A path under the working directory dispatches as-is")
    func pathUnderTheRootDispatches() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["cli:test": ["echo.yaml"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))

        // When
        let result = try await method.handle(request(["token": .string(token), "path": "echo.yaml"]), claims: try #require(authority.verify(token)))

        // Then
        #expect(result["status"]?.stringValue == "ok")
        #expect(result["path"]?.stringValue == "echo.yaml")
    }

    @Test("A path that climbs out of an allowed folder is refused, though the file it lands on exists")
    func pathClimbingOutOfAnAllowedFolderRefused() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["cli:x": ["a/*"]])
        let token = authority.mint(TokenClaims(principal: "cli:x"))
        let claims = try #require(authority.verify(token))

        // When
        let error = try await #require(throws: ResourceError.self) {
            try await method.handle(request(["token": .string(token), "path": "a/../echo.yaml"]), claims: claims)
        }

        // Then
        #expect(error.message.contains("'a/../echo.yaml'"), Comment(rawValue: error.message))
    }

    @Test("Rejected when neither path nor spec is given")
    func missingPathAndSpecRejected() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["*": ["*"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))
        do {

        // When
            _ = try await method.handle(request(["token": .string(token)]), claims: try #require(authority.verify(token)))

        // Then
            Issue.record("Should be rejected when neither path nor spec is present")
        } catch is ProtocolError {
        }
    }

    // MARK: - token
    @Test("Calling with a workflow token attaches as a nested run")
    func workflowTokenDispatchesAsNested() async throws {
        // Given
        let (method, authority, registry) = try await makeMethod(policy: ["cli:parent": ["echo.yaml"]])
        await registry.register(WorkRecord(
                runID: "wf-parent",
                workflowName: "parent",
                principal: "cli:parent",
                origin: .rpc,
                rootID: "trace-xyz",
                nodeID: "span-1",
                correlator: "corr-1",
                parameters: nil
        ))
        let token = authority.mint(TokenClaims(principal: "cli:parent", runID: "wf-parent"))

        // When
        let result = try await method.handle(request(["token": .string(token), "path": "echo.yaml"]), claims: try #require(authority.verify(token)))

        // Then
        #expect(result["status"]?.stringValue == "ok")
        #expect(result["path"]?.stringValue == "echo.yaml")
    }

    @Test("A token of a finished run is rejected")
    func dispatchRejectsStaleRunToken() async throws {
        // Given
        let directory = try temporary.make("stale")
        defer { try? FileManager.default.removeItem(at: directory) }
        try echoWorkflowYAML.write(
            to: directory.appendingPathComponent("echo2.yaml"), atomically: true, encoding: .utf8)
        let reader = try WorkflowReader(directory: directory)
        let authority = TokenAuthority()
        let registry = WorkRegistry()
        let runner = WorkflowRunner(
            workflows: reader,
            eventBus: WorkflowEventBus(),
            policyStore: PolicyStore(seed: ["*": ["*"]]),
            pool: WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max),
            workRegistry: registry,
            tokenAuthority: authority,
            capabilities: CapabilitySet(
                shell: LiveShell(),
                agent: LiveAgent(executor: AgentExecutor(backend: StubBackend())),
                resources: LiveResources(workingDirectory: WorkingDirectory(directory: nil))
            ))
        let method = WorkflowDispatchMethod(runner: runner, workflows: reader,
            workRegistry: registry)
        let stale = authority.mint(TokenClaims(principal: "cli:gone", runID: "wf-gone"))
        do {
            _ = try await method.handle(RPCRequest(id: "r1", method: "workflow.dispatch",
                    params: ["token": .string(stale), "path": "echo2.yaml"]), claims: try #require(authority.verify(stale)))

        // Then
            Issue.record("A stale run token should be rejected")
        } catch {
            #expect("\(error)".contains("finished run"), "\(error)")
        }
    }

    // MARK: - Private

    private var echoWorkflowYAML: String {
        workflowFile("""
        failing: [nonzero_exit, timeout]
        body:
          - let: x
            value: { call: { procedure: shell, arguments: { command: ["/bin/echo", "ok"] } } }
        returns: "Dictionary<String, Any>"
        result: { dictionary: [ [v, { ref: x }] ] }
        """)
    }

    private func makeMethod(policy: [String: [String]]) async throws

    -> (WorkflowDispatchMethod, TokenAuthority, WorkRegistry) {
        let directory = try temporary.make("wf")
        try echoWorkflowYAML.write(to: directory.appendingPathComponent("echo.yaml"), atomically: true, encoding: .utf8)
        let reader = try WorkflowReader(directory: directory)
        let authority = TokenAuthority()
        let registry = WorkRegistry()
        let runner = WorkflowRunner(
            workflows: reader,
            eventBus: WorkflowEventBus(),
            policyStore: PolicyStore(seed: policy),
            pool: WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max),
            workRegistry: registry,
            tokenAuthority: authority,
            capabilities: CapabilitySet(
                shell: LiveShell(),
                agent: LiveAgent(executor: AgentExecutor(backend: StubBackend("noop"))),
                resources: LiveResources(workingDirectory: WorkingDirectory(directory: nil))
            ))
        let method = WorkflowDispatchMethod(runner: runner, workflows: reader,
            workRegistry: registry)

        return (method, authority, registry)
    }

    private func request(_ params: [String: JSONValue]) -> RPCRequest {
        RPCRequest(id: "r-\(UUID().uuidString.prefix(6))", method: "workflow.dispatch", params: params)
    }
}
