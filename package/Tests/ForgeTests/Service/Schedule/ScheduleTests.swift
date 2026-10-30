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
    @Test("A schedule with an inline spec runs as the inline sigil")
    func inlineSpecRunsAsInline() throws {
        // Given
        let json = #"{"every":"1h","spec":{"body":[]}}"#

        // When
        let sut = try JSONDecoder().decode(Schedule.self, from: Data(json.utf8))

        // Then
        #expect(sut.workflow == WorkflowCatalog.inlineSigil)
        #expect(sut.spec == ["body": []])
    }

    @Test("A schedule writing a workflow and a spec both is refused")
    func workflowAndSpecRefused() throws {
        // Given
        let json = #"{"workflow":"<inline>","every":"1h","spec":{"body":[]}}"#

        // When
        let error = #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Schedule.self, from: Data(json.utf8))
        }

        // Then
        guard case let .dataCorrupted(context)? = error else {
            Issue.record("expected dataCorrupted, got \(String(describing: error))")

            return
        }

        #expect(context.debugDescription.contains("mutually exclusive"))
    }

    @Test("A schedule with an inline spec writes no workflow")
    func inlineSpecWritesNoWorkflow() throws {
        // Given
        let sut = Schedule(
            id: "s",
            workflow: WorkflowCatalog.inlineSigil,
            trigger: .every(Interval(seconds: 60)),
            spec: ["body": []]
        )

        // When
        let written = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(sut))

        // Then
        #expect(written.objectValue?["workflow"] == nil)
        #expect(try JSONDecoder().decode(Schedule.self, from: JSONEncoder().encode(sut)).workflow == WorkflowCatalog.inlineSigil)
    }

    // MARK: - Public
    // MARK: - Private
}
