//
//  ScheduleCreateTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/26/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("ScheduleCreate Tests")
struct ScheduleCreateTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("schedulecreate")

    // MARK: - Initializer
    // MARK: - Test
    @Test("A refused inline spec gives the refusal's message as its reason")
    func refusedSpecGivesTheRefusalMessage() async throws {
        // Given
        let directory = try temporary.make("refused")
        defer { try? FileManager.default.removeItem(at: directory) }
        let authority = TokenAuthority()
        let catalog = try WorkflowCatalog(directory: nil)
        let method = ScheduleCreateMethod(
            store: ScheduleStore(configDir: nil, runtimeDirectory: directory, stateFile: directory.appendingPathComponent("enabled.json")),
            catalog: catalog,
            policyStore: PolicyStore(seed: ["cli:response": ["<inline>"]]))
        let token = authority.mint(TokenClaims(principal: "cli:response"))
        let badSpec: [String: JSONValue] = [
            "body": [["let": "x", "value": ["format": 5]]],
        ]
        let refusal = await #expect(throws: WorkflowValidationError.self) {
            try await catalog.inline(.object(badSpec))
        }

        // When
        let error = await #expect(throws: ProtocolError.self) {
            try await method.handle(RPCRequest(
                    id: "q1", method: "schedule.create",
                    params: ["token": .string(token), "spec": .object(badSpec), "after": "1h"]), claims: try #require(authority.verify(token)))
        }

        // Then
        #expect(error?.message == "schedule.create: malformed 'spec' — \(try #require(refusal).message)")
    }

    // MARK: - Public
    // MARK: - Private
}
