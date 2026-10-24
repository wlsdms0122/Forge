//
//  ScheduleTests.swift
//  ForgeTests
//
//  Created by JSilver on 10/25/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("Schedule Tests")
struct ScheduleTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("A schedule with an inline spec names its workflow <inline>")
    func inlineSpecRunsAsInline() throws {
        // Given
        let json = #"{"workflow":"<inline>","every":"1h","spec":{"body":[]}}"#

        // When
        let sut = try JSONDecoder().decode(Schedule.self, from: Data(json.utf8))

        // Then
        #expect(sut.workflow == WorkflowCatalog.inlineSigil)
        #expect(sut.spec != nil)
    }

    @Test("A schedule with an inline spec and another workflow name is refused")
    func inlineSpecRefusesAnotherName() throws {
        // Given
        let json = #"{"workflow":"nightly","every":"1h","spec":{"body":[]}}"#

        // When
        let error = #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Schedule.self, from: Data(json.utf8))
        }

        // Then
        guard case let .dataCorrupted(context)? = error else {
            Issue.record("expected dataCorrupted, got \(String(describing: error))")

            return
        }

        #expect(context.debugDescription.contains("'workflow' must be '<inline>'"))
    }

    // MARK: - Public
    // MARK: - Private
}
