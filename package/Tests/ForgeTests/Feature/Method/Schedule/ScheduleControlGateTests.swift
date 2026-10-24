//
//  ScheduleControlGateTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("ScheduleControlGate Tests")
struct ScheduleControlGateTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("ctlgate")

    private let inlineSpec: [String: JSONValue] = [
        "failing": ["nonzero_exit", "timeout"],
            "body": [["let": "x", "value": ["call": ["procedure": "shell", "arguments": ["command": ["/bin/echo", "ok"]]]]]],
    ]
    
    // MARK: - Initializer
    // MARK: - Test
    @Test("Delete by an unauthorized principal is rejected")
    func deleteDeniedForUnauthorizedPrincipal() async throws {
        // Given
        let directory = try temporary.make("del-deny"); defer { try? FileManager.default.removeItem(at: directory) }
        let authority = TokenAuthority()
        let (store, id) = try await seedSchedule(directory, authority)
        let del = ScheduleDeleteMethod(
            store: store, policyStore: PolicyStore(seed: ["cli:owner": ["<inline>"]]))
        let attacker = authority.mint(TokenClaims(principal: "cli:attacker"))
        do {
            _ = try await del.handle(RPCRequest(id: "d", method: "schedule.delete",
                    params: ["token": .string(attacker), "id": .string(id)]), claims: try #require(authority.verify(attacker)))

        // Then
            Issue.record("Delete by an out-of-scope principal should be rejected")
        } catch {
            #expect(String(describing: error).contains("not allowed"), "Should be a policy denial: \(error)")
        }

        let still = await store.reload().entries
        #expect(still.count == 1, "A rejected delete should leave the schedule in place")
    }
    
    @Test("An authorized principal can delete")
    func deleteAllowedForAuthorizedPrincipal() async throws {
        // Given
        let directory = try temporary.make("del-allow"); defer { try? FileManager.default.removeItem(at: directory) }
        let authority = TokenAuthority()
        let (store, id) = try await seedSchedule(directory, authority)
        let del = ScheduleDeleteMethod(
            store: store, policyStore: PolicyStore(seed: ["cli:owner": ["<inline>"]]))
        let owner = authority.mint(TokenClaims(principal: "cli:owner"))
        let result = try await del.handle(RPCRequest(id: "d", method: "schedule.delete",
                params: ["token": .string(owner), "id": .string(id)]), claims: try #require(authority.verify(owner)))

        // Then
        #expect(result["deleted"]?.boolValue == true)
        let remaining = await store.reload().entries
        #expect(remaining.isEmpty, "A permitted delete should remove the schedule")
    }
    
    @Test("An unauthorized principal cannot toggle on/off either")
    func setEnabledDeniedForUnauthorizedPrincipal() async throws {
        // Given
        let directory = try temporary.make("toggle-deny"); defer { try? FileManager.default.removeItem(at: directory) }
        let authority = TokenAuthority()
        let (store, id) = try await seedSchedule(directory, authority)
        let toggle = ScheduleSetEnabledMethod(
            store: store, policyStore: PolicyStore(seed: ["cli:owner": ["<inline>"]]))
        let attacker = authority.mint(TokenClaims(principal: "cli:attacker"))
        do {
            _ = try await toggle.handle(RPCRequest(id: "t", method: "schedule.set_enabled",
                    params: ["token": .string(attacker), "id": .string(id), "enabled": false]), claims: try #require(authority.verify(attacker)))

        // Then
            Issue.record("Toggle by an out-of-scope principal should be rejected")
        } catch {
            #expect(String(describing: error).contains("not allowed"), "Should be a policy denial: \(error)")
        }
    }
    
    // MARK: - Private
    
    private func seedSchedule(_ directory: URL, _ authority: TokenAuthority) async throws -> (ScheduleStore, String) {
        let store = ScheduleStore(
            configDir: nil, runtimeDirectory: directory,
            stateFile: FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-sched-enabled-\(UUID().uuidString.prefix(6)).json"))
        let create = ScheduleCreateMethod(
            store: store, workflowStore: try WorkflowCatalog(directory: nil),
            policyStore: PolicyStore(seed: ["cli:owner": ["<inline>"]]))
        let ownerToken = authority.mint(TokenClaims(principal: "cli:owner"))
        _ = try await create.handle(RPCRequest(
                id: "c", method: "schedule.create",
                params: ["token": .string(ownerToken), "spec": .object(inlineSpec), "after": "1h"]), claims: try #require(authority.verify(ownerToken)))
        let entries = await store.reload().entries
        let scheduleID = try #require(entries.first?.schedule.id)
        
        return (store, scheduleID)
    }
}
