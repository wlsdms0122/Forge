//
//  CreatePolicyGateTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("CreatePolicyGate Tests")
struct CreatePolicyGateTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("creategate")

    private let inlineSpec: [String: Any] = [
        "body": [["id": "x", "shell": ["command": ["/bin/echo", "ok"]]]],
    ]
    
    // MARK: - Initializer
    // MARK: - Test
    // MARK: - schedule.create (one-shot: after)
    @Test("One-shot create passes when policy allows it")
    func oneShotCreateAllowedByPolicy() async throws {
        // Given
        let directory = try temporary.make("once-allow")
        defer { try? FileManager.default.removeItem(at: directory) }
        let authority = TokenAuthority()
        let method = ScheduleCreateMethod(
            store: ScheduleStore(configDir: nil, runtimeDirectory: directory, stateFile: FileManager.default.temporaryDirectory.appendingPathComponent("forge-sched-enabled-\(UUID().uuidString.prefix(6)).json")),
            workflowStore: SpecCatalog(directory: nil, loader: ForgeSpec.loader()),
            policyStore: PolicyStore(seed: ["cli:response": ["<inline>"]]),
            tokenAuthority: authority)
        let token = authority.mint(TokenClaims(principal: "cli:response"))
        let result = try await method.handle(RPCRequest(
                id: "q1", method: "schedule.create",
                params: ["token": token, "spec": inlineSpec, "after": "1h"]))

        // Then
        #expect(result.dict["workflow"] as? String == "<inline>")
    }
    
    @Test("One-shot create is rejected when policy blocks it")
    func oneShotCreateDeniedByPolicy() async throws {
        // Given
        let directory = try temporary.make("once-deny")
        defer { try? FileManager.default.removeItem(at: directory) }
        let authority = TokenAuthority()
        let store = ScheduleStore(configDir: nil, runtimeDirectory: directory, stateFile: FileManager.default.temporaryDirectory.appendingPathComponent("forge-sched-enabled-\(UUID().uuidString.prefix(6)).json"))
        let method = ScheduleCreateMethod(
            store: store,
            workflowStore: SpecCatalog(directory: nil, loader: ForgeSpec.loader()),
            policyStore: PolicyStore(seed: ["cli:response": ["worker"]]),
            tokenAuthority: authority)
        let token = authority.mint(TokenClaims(principal: "cli:<inline>"))
        do {
            _ = try await method.handle(RPCRequest(
                    id: "q2", method: "schedule.create",
                    params: ["token": token, "spec": inlineSpec, "after": "1h"]))

        // Then
            Issue.record("Registration by a principal absent from the policy should be rejected")
        } catch {
            #expect(String(describing: error).contains("not allowed"), "Rejection reason should be a policy denial: \(error)")
        }

        let entries = await store.catalog().entries
        #expect(entries.isEmpty, "A rejected registration should leave no file behind")
    }

    // MARK: - schedule.create (recurring: every)
    @Test("Schedule create is rejected when policy blocks it")
    func scheduleCreateDeniedByPolicy() async throws {
        // Given
        let directory = try temporary.make("sched-deny")
        defer { try? FileManager.default.removeItem(at: directory) }
        let authority = TokenAuthority()
        let store = ScheduleStore(configDir: nil, runtimeDirectory: directory, stateFile: FileManager.default.temporaryDirectory.appendingPathComponent("forge-sched-enabled-\(UUID().uuidString.prefix(6)).json"))
        let method = ScheduleCreateMethod(
            store: store,
            workflowStore: SpecCatalog(directory: nil, loader: ForgeSpec.loader()),
            policyStore: PolicyStore(seed: ["system:*": ["*"]]),
            tokenAuthority: authority)
        let token = authority.mint(TokenClaims(principal: "cli:response"))
        do {
            _ = try await method.handle(RPCRequest(
                    id: "q3", method: "schedule.create",
                    params: ["token": token, "spec": inlineSpec, "every": "1h"]))

        // Then
            Issue.record("Registration by a principal absent from the policy should be rejected")
        } catch {
            #expect(String(describing: error).contains("not allowed"), "Rejection reason should be a policy denial: \(error)")
        }

        let entries = await store.catalog().entries
        #expect(entries.isEmpty, "A rejected registration should leave no file behind")
    }

    @Test("Schedule create passes when policy allows it")
    func scheduleCreateAllowedByPolicy() async throws {
        // Given
        let directory = try temporary.make("sched-allow")
        defer { try? FileManager.default.removeItem(at: directory) }
        let authority = TokenAuthority()
        let method = ScheduleCreateMethod(
            store: ScheduleStore(configDir: nil, runtimeDirectory: directory, stateFile: FileManager.default.temporaryDirectory.appendingPathComponent("forge-sched-enabled-\(UUID().uuidString.prefix(6)).json")),
            workflowStore: SpecCatalog(directory: nil, loader: ForgeSpec.loader()),
            policyStore: PolicyStore(seed: ["cli:*": ["<inline>"]]),
            tokenAuthority: authority)
        let token = authority.mint(TokenClaims(principal: "cli:response"))
        let result = try await method.handle(RPCRequest(
                id: "q4", method: "schedule.create",
                params: ["token": token, "spec": inlineSpec, "every": "1h"]))

        // Then
        #expect(result.dict["workflow"] as? String == "<inline>")
    }
    
    // MARK: - Private
}
