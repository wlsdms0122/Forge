//
//  ScheduleCreateCommandTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/29/26.
//

import Foundation
import Testing
@testable import Forge
@testable import ForgeCLI

@Suite("ScheduleCreateCommand Tests")
struct ScheduleCreateCommandTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("The inline spec the help shows loads as the daemon loads it")
    func helpInlineSpecLoads() async throws {
        // Given
        let sut = ScheduleCreateCommand.configuration.discussion
        let opening = try #require(sut.range(of: "--spec '"))
        let closing = try #require(sut[opening.upperBound...].firstIndex(of: "'"))
        let text = String(sut[opening.upperBound..<closing])
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        let spec = try #require(try JSONValue(jsonObject: object).objectValue)
        let reader = try WorkflowReader(directory: nil)

        // When
        let workflow = try await reader.inline(spec)

        // Then
        #expect(workflow.path == Workflow.inlineSigil)
    }

    // MARK: - Public
    // MARK: - Private
}
