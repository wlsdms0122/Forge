//
//  RPCResponseTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/24/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("RPCResponse Tests")
struct RPCResponseTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("an error's wire details ride beside its type and message")
    func errorCarriesItsWireDetails() throws {
        // Given
        let error = BackendNonzeroExit("exited 2", exitCode: 2, stderr: "err", stdout: "out")

        // When
        let sut = RPCResponse(id: "1", error: error)
        let line = try sut.encode()

        // Then
        let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        let wire = try #require(object["error"] as? [String: Any])
        #expect(wire["type"] as? String == "BackendNonzeroExit")
        #expect(wire["message"] as? String == "exited 2")
        #expect(wire["exit_code"] as? Int == 2)
        #expect(wire["stderr"] as? String == "err")
        #expect(wire["stdout"] as? String == "out")
    }

    // MARK: - Public
    // MARK: - Private
}
