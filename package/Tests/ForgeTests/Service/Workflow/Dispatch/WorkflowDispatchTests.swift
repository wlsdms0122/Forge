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

    private var anonSpec: [String: Any] {
        [
            "steps": [
                ["id": "x", "shell": ["command": ["/bin/echo", "ok"]]],
            ],
            "outputs": ["v": ["ref": "x"]],
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
        let result = try await method.handle(request(["token": token, "spec": anonSpec]))

        // Then
        #expect(result.dict["status"] as? String == "ok")
        #expect(result.dict["name"] as? String == WorkflowDispatchMethod.inlineSigil, "The result name of an inline run is fixed to the sigil")
    }

    @Test("Run id is freshly minted — the wire id is not borrowed")
    func runIDMintedNotBorrowedFromWireID() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["*": ["*"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))
        let wireID = "fc-client-collide"
        let first = try await method.handle(RPCRequest(id: wireID, method: "workflow.dispatch",
                params: ["token": token, "spec": anonSpec]))

        // Then
        let firstID = try #require(first.dict["workflow_id"] as? String)
        #expect(firstID.hasPrefix("wf-"), "runID should be forge-minted (wf-*) — borrowing the wire id is forbidden (finding J): \(firstID)")
        #expect(firstID != wireID, "runID must not equal the client wire id")
        let second = try await method.handle(RPCRequest(id: wireID, method: "workflow.dispatch",
                params: ["token": token, "spec": anonSpec]))
        let secondID = try #require(second.dict["workflow_id"] as? String)
        #expect(firstID != secondID, "Two dispatches with the same wire id sharing a runID means cross-run contamination (finding J)")
    }

    @Test("An inline spec with a name attached is rejected")
    func inlineSpecWithNameRejected() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["cli:test": ["<inline>"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))
        var named = anonSpec
        named["name"] = "echo"
        do {

        // When
            _ = try await method.handle(request(["token": token, "spec": named]))

        // Then
            Issue.record("An inline spec with a name key should be rejected")
        } catch let error as ProtocolError {
            #expect(error.message.contains("name"), "The error should explain the name prohibition: \(error.message)")
        }
    }

    @Test("An inline spec is rejected without the sigil policy")
    func inlineSpecDeniedWithoutSigilPolicy() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["cli:test": ["echo"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))
        do {

        // When
            _ = try await method.handle(request(["token": token, "spec": anonSpec]))

        // Then
            Issue.record("Should be rejected without an <inline> policy")
        } catch let error as PolicyDenied {
            #expect(error.message.contains(WorkflowDispatchMethod.inlineSigil), "The denial reason should include the sigil: \(error.message)")
        }
    }

    @Test("A wildcard policy also allows inline")
    func wildcardPolicyAllowsInline() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["*": ["*"]])
        let token = authority.mint(TokenClaims(principal: "cli:anything"))

        // When
        let result = try await method.handle(request(["token": token, "spec": anonSpec]))

        // Then
        #expect(result.dict["status"] as? String == "ok")
    }

    @Test("A malformed spec answers with a readable error")
    func malformedSpecGivesFriendlyError() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["*": ["*"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))
        let badSpec: [String: Any] = [
            "steps": [["shell": ["command": ["echo", "hi"]]]],
        ]
        do {

        // When
            _ = try await method.handle(request(["token": token, "spec": badSpec]))

        // Then
            Issue.record("A malformed spec should be rejected")
        } catch let error as ProtocolError {
            #expect(error.message.contains("steps[0]"), "JSON path notation: \(error.message)")
            #expect(error.message.contains("'id'"), "Missing key named explicitly: \(error.message)")
            #expect(!error.message.contains("CodingKeys"), "Raw Swift errors must not leak: \(error.message)")
        }
    }

    @Test("An inline spec containing an invalid reference is rejected")
    func inlineSpecWithInvalidRefRejected() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["*": ["*"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))
        let badSpec: [String: Any] = [
            "steps": [
                ["id": "a", "shell": ["command": ["/bin/echo", ["ref": "nonexistent"]]]],
            ],
        ]
        do {

        // When
            _ = try await method.handle(request(["token": token, "spec": badSpec]))

        // Then
            Issue.record("A spec containing an undeclared ref should be rejected at dispatch")
        } catch let error as ProtocolError {
            #expect(error.message.contains("malformed 'spec'"), "Validation failure message: \(error.message)")
            #expect(error.message.contains("nonexistent"), "Undeclared ref named explicitly: \(error.message)")
        }
    }

    // MARK: - registered name
    @Test("A registered name dispatches as-is")
    func registeredNameDispatches() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["cli:test": ["echo"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))

        // When
        let result = try await method.handle(request(["token": token, "name": "echo"]))

        // Then
        #expect(result.dict["status"] as? String == "ok")
        #expect(result.dict["name"] as? String == "echo")
    }

    @Test("Rejected when neither name nor spec is given")
    func missingNameAndSpecRejected() async throws {
        // Given
        let (method, authority, _) = try await makeMethod(policy: ["*": ["*"]])
        let token = authority.mint(TokenClaims(principal: "cli:test"))
        do {

        // When
            _ = try await method.handle(request(["token": token]))

        // Then
            Issue.record("Should be rejected when neither name nor spec is present")
        } catch is ProtocolError {
        }
    }

    // MARK: - token
    @Test("Cannot dispatch without a token")
    func tokenRequired() async throws {
        // Given
        let (method, _, _) = try await makeMethod(policy: ["*": ["*"]])
        do {

        // When
            _ = try await method.handle(request(["name": "echo"]))

        // Then
            Issue.record("Should be rejected without a token")
        } catch is ProtocolError {
        }
    }

    @Test("Calling with a workflow token attaches as a nested run")
    func workflowTokenDispatchesAsNested() async throws {
        // Given
        let (method, authority, registry) = try await makeMethod(policy: ["cli:parent": ["echo"]])
        await registry.register(WorkRecord(
                workflowID: "wf-parent",
                workflowName: "parent",
                principal: "cli:parent",
                origin: .rpc,
                rootID: "trace-xyz",
                nodeID: "span-1",
                correlator: "corr-1",
                parameters: nil
        ))
        let token = authority.mint(TokenClaims(principal: "cli:parent", workflowID: "wf-parent"))

        // When
        let result = try await method.handle(request(["token": token, "name": "echo"]))

        // Then
        #expect(result.dict["status"] as? String == "ok")
        #expect(result.dict["name"] as? String == "echo")
    }

    @Test("A token of a finished run is rejected")
    func dispatchRejectsStaleRunToken() async throws {
        // Given
        let directory = try temporary.make("stale")
        defer { try? FileManager.default.removeItem(at: directory) }
        try echoWorkflowYAML(name: "echo2").write(
            to: directory.appendingPathComponent("echo2.yaml"), atomically: true, encoding: .utf8)
        let store = SpecCatalog(directory: directory, loader: ForgeSpec.loader())
        let authority = TokenAuthority()
        let registry = WorkRegistry()
        let runner = SpecWorkflowRunner(
            catalog: store,
            eventBus: WorkflowEventBus(),
            policyStore: PolicyStore(seed: ["*": ["*"]]),
            pool: WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max),
            workRegistry: registry,
            tokenAuthority: authority,
            shell: LiveShell(),
            agent: LiveAgent(executor: Executor(backend: StubBackend())),
            resources: LiveResources(store: ResourceStore(directory: nil)))
        let method = WorkflowDispatchMethod(runner: runner, store: store,
            workRegistry: registry, tokenAuthority: authority)
        let stale = authority.mint(TokenClaims(principal: "cli:gone", workflowID: "wf-gone"))
        do {
            _ = try await method.handle(RPCRequest(id: "r1", method: "workflow.dispatch",
                    params: ["token": stale, "name": "echo2"]))

        // Then
            Issue.record("A stale run token should be rejected")
        } catch {
            #expect("\(error)".contains("finished run"), "\(error)")
        }
    }

    // MARK: - Private

    private func echoWorkflowYAML(name: String) -> String {
        """
        name: \(name)
        steps:
          - id: x
            shell:
              command: ["/bin/echo", "ok"]
        outputs:
          v: { ref: x }
        """
    }

    private func makeMethod(policy: [String: [String]]) async throws

    -> (WorkflowDispatchMethod, TokenAuthority, WorkRegistry) {
        let directory = try temporary.make("wf")
        try echoWorkflowYAML(name: "echo").write(to: directory.appendingPathComponent("echo.yaml"), atomically: true, encoding: .utf8)
        let store = SpecCatalog(directory: directory, loader: ForgeSpec.loader())
        let authority = TokenAuthority()
        let registry = WorkRegistry()
        let runner = SpecWorkflowRunner(
            catalog: store,
            eventBus: WorkflowEventBus(),
            policyStore: PolicyStore(seed: policy),
            pool: WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max),
            workRegistry: registry,
            tokenAuthority: authority,
            shell: LiveShell(),
            agent: LiveAgent(executor: Executor(backend: StubBackend("noop"))),
            resources: LiveResources(store: ResourceStore(directory: nil)))
        let method = WorkflowDispatchMethod(runner: runner, store: store,
            workRegistry: registry, tokenAuthority: authority)

        return (method, authority, registry)
    }

    private func request(_ params: [String: Any]) -> RPCRequest {
        RPCRequest(id: "r-\(UUID().uuidString.prefix(6))", method: "workflow.dispatch", params: params)
    }
}
