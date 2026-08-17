//
//  ServiceScopedGateTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("ServiceScopedGate Tests")
struct ServiceScopedGateTests {
    private actor CollectingSink: EventSink {
        func emit(_ object: JSONObject) async {}
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    // MARK: authz unit — policy layer (ServiceAuthz), claims already verified
    @Test("Acting as its own service is allowed")
    func actingAsAcceptsMatchingService() throws {
        try ServiceAuthz.requireActingAs("slack", claims: TokenClaims(principal: "service:slack"), method: "m")
    }
    
    @Test("Acting as another service is rejected")
    func actingAsRejectsMismatchedService() throws {
        let error = try #require(throws: (any Error).self) {
            try ServiceAuthz.requireActingAs(
                "slack", claims: TokenClaims(principal: "service:jira"), method: "m")
        }
        
        #expect(String(describing: error).contains("service:jira"), "denial reason should expose the principal: \(error)")
    }
    
    @Test("An operator can act as any service")
    func actingAsAllowsOperatorAnyService() throws {
        for principal in ["system:admin", "system:runner", "admin:jineun"] {
            try ServiceAuthz.requireActingAs("slack", claims: TokenClaims(principal: principal), method: "m")
        }
    }
    
    @Test("Global control is not possible with a service token")
    func globalRejectsServiceToken() throws {
        let error = try #require(throws: (any Error).self) {
            try ServiceAuthz.requireGlobal(
                claims: TokenClaims(principal: "service:jira"), method: "service.reload")
        }
        
        #expect(String(describing: error).contains("global service control"), "\(error)")
        try ServiceAuthz.requireGlobal(claims: TokenClaims(principal: "system:admin"), method: "service.reload")
    }
    
    // MARK: register — cross-service hijack blocked at the method
    @Test("Cannot register with another service's token")
    func registerRejectsCrossServiceToken() async throws {
        // Given
        let authority = TokenAuthority()
        let bus = WorkflowHandlerBus()
        let method = SessionHandlerRegisterMethod(handlerBus: bus, tokenAuthority: authority)
        let jira = authority.mint(TokenClaims(principal: "service:jira"))
        actor ErrorBox {
            var error: Error?
            
            func set(_ error: Error) { self.error = error }
        }
        
        let box = ErrorBox()
        let task = Task {
            do {
                try await method.handle(
                    RPCRequest(id: "r", method: "session.handler.register",
                        params: ["token": jira, "service": "slack"]),
                    sink: CollectingSink())
            } catch { await box.set(error) }
        }
        
        var rejected = false
        for _ in 0..<100 {
            if await !bus.listing().isEmpty { break }
            if let error = await box.error {

        // Then
                #expect(String(describing: error).contains("service:jira"), "should be a service-scope denial: \(error)")
                rejected = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        let listing = await bus.listing()
        #expect(rejected && listing.isEmpty, "slack registration with a service:jira token must be rejected before reaching the bus — listing=\(listing.map(\.0))")
    }
    
    @Test("Registration succeeds with its own service token")
    func registerAllowsOwnServiceToken() async throws {
        // Given
        let authority = TokenAuthority()
        let bus = WorkflowHandlerBus()
        let method = SessionHandlerRegisterMethod(handlerBus: bus, tokenAuthority: authority)
        let slack = authority.mint(TokenClaims(principal: "service:slack"))
        let task = Task {
            try await method.handle(
                RPCRequest(id: "r", method: "session.handler.register",
                    params: ["token": slack, "service": "slack"]),
                sink: CollectingSink())
        }
        
        var registered = false
        for _ in 0..<100 {
            if await !bus.listing().isEmpty { registered = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()

        // Then
        #expect(registered, "registering under its own name should pass")
    }
    
    // MARK: ack — forged cross-service delivery blocked
    @Test("Cannot ack with another service's token")
    func ackRejectsCrossServiceToken() async throws {
        // Given
        let authority = TokenAuthority()
        let ack = SessionHandlerAckMethod(handlerBus: WorkflowHandlerBus(), tokenAuthority: authority)
        let jira = authority.mint(TokenClaims(principal: "service:jira"))
        do {
            _ = try await ack.handle(RPCRequest(
                    id: "a", method: "session.handler.ack",
                    params: ["token": jira, "service": "slack", "message_id": "m1", "result": [String: Any]()]))

        // Then
            Issue.record("slack ack with a service:jira token must be rejected")
        } catch {
            #expect(String(describing: error).contains("service:jira"), "should be a service-scope denial: \(error)")
        }
    }
    
    // MARK: named service control — same act-as binding (review finding: the invariant's
    @Test("Cannot shut down with another service's token")
    func shutdownRejectsCrossServiceToken() async throws {
        // Given
        let authority = TokenAuthority()
        let sup = ServiceSupervisor(services: [], runtimeDirectory: FileManager.default.temporaryDirectory,
            tokenAuthority: authority)
        let method = ServiceShutdownMethod(supervisor: sup, tokenAuthority: authority)
        let jira = authority.mint(TokenClaims(principal: "service:jira"))
        do {
            _ = try await method.handle(RPCRequest(
                    id: "s", method: "service.shutdown", params: ["token": jira, "name": "slack"]))

        // Then
            Issue.record("slack shutdown with a service:jira token must be rejected")
        } catch {
            #expect(String(describing: error).contains("service:jira"), "should be a service-scope denial: \(error)")
        }
    }
    
    @Test("Ack succeeds with its own service token")
    func ackAllowsOwnServiceToken() async throws {
        // Given
        let authority = TokenAuthority()
        let ack = SessionHandlerAckMethod(handlerBus: WorkflowHandlerBus(), tokenAuthority: authority)
        let slack = authority.mint(TokenClaims(principal: "service:slack"))
        let result = try await ack.handle(RPCRequest(
                id: "a", method: "session.handler.ack",
                params: ["token": slack, "service": "slack", "message_id": "m1", "result": [String: Any]()]))

        // Then
        #expect(result.dict["ok"] as? Bool == true)
    }
    
    // MARK: global control — reload is *narrower* than named control (review finding: the
    @Test("Reload is not open to service tokens")
    func reloadRejectsServiceToken() async throws {
        // Given
        let authority = TokenAuthority()
        let sup = ServiceSupervisor(services: [], runtimeDirectory: FileManager.default.temporaryDirectory,
            tokenAuthority: authority)
        let method = ServiceReloadMethod(supervisor: sup, tokenAuthority: authority,
            configPath: nil,
            sessionHome: FileManager.default.temporaryDirectory,
            configSnapshot: ConfigSnapshot(ConfigReport(tomlPath: nil, entries: [])))
        let jira = authority.mint(TokenClaims(principal: "service:jira"))
        do {
            _ = try await method.handle(RPCRequest(
                    id: "g", method: "service.reload", params: ["token": jira]))

        // Then
            Issue.record("global reload with a service token must be rejected")
        } catch {
            #expect(String(describing: error).contains("global service control"), "should be a global-gate denial: \(error)")
        }
    }
    
    @Test("Denial wording comes from a single owner across all gates — it does not vary per gate")
    func policyDenialMessageIsUniformAcrossServiceGates() async throws {
        // Given
        let store = SpecCatalog(directory: nil, loader: ForgeSpec.loader())
        let bus = WorkflowEventBus()
        let authority = TokenAuthority()
        let runner = SpecWorkflowRunner(
            catalog: store,
            eventBus: bus,
            policyStore: PolicyStore(seed: ["system:other": ["*"]]),
            pool: WorkflowPool(maximumConcurrentSteps: Int.max, maximumActiveRuns: Int.max),
            workRegistry: WorkRegistry(),
            tokenAuthority: authority,
            shell: LiveShell(),
            agent: LiveAgent(executor: Executor(backend: StubBackend("noop"))),
            resources: LiveResources(store: ResourceStore(directory: nil)))
        let dispatchMethod = WorkflowDispatchMethod(runner: runner, store: store,
            workRegistry: WorkRegistry(),
            tokenAuthority: authority)
        let streamMethod = WorkflowDispatchStreamMethod(dispatchMethod: dispatchMethod, eventBus: bus)
        let token = authority.mint(TokenClaims(principal: "system:rpc"))
        let spec: [String: Any] = ["body": [["id": "x", "shell": ["command": ["/bin/echo", "n"]]]]]
        var messages: [String] = []
        do {
            _ = try await dispatchMethod.handle(RPCRequest(
                    id: "r-async", method: "workflow.dispatch",
                    params: ["token": token, "spec": spec, "async": true]))

        // Then
            Issue.record("async gate should deny")
        } catch let denial as PolicyDenied { messages.append(denial.message) }
        do {
            try await streamMethod.handle(RPCRequest(
                    id: "r-stream", method: "workflow.dispatch_stream",
                    params: ["token": token, "spec": spec]), sink: CollectingSink())
            Issue.record("stream gate should deny")
        } catch let denial as PolicyDenied { messages.append(denial.message) }
        #expect(messages.count == 2)
        #expect(Set(messages).count == 1, "per-gate wording must not diverge: \(messages)")
        #expect(!messages[0].contains("refused"), "the drifted '— refused' tail was removed during convergence")
    }
    
    // MARK: - Private
}
