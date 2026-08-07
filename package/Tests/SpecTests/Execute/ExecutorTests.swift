//
//  ExecutorTests.swift
//  SpecTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
@testable import Spec

@Suite
struct ExecutorTests {
    // MARK: - Property
    private let loader = SpecLoader.testing

    // MARK: - Initializer
    // MARK: - Test
    @Test("bindings flow through a step sequence")
    func bindingsFlowThroughSequence() async throws {
        // Given
        let spec = try loader.load("""
        name: sequence
        inputs:
          who: string
        steps:
          - id: greeting
            value: { format: "hello, ${who}", with: { who: { ref: inputs.who } } }
          - id: loud
            value: { format: "${text}!", with: { text: { ref: greeting } } }
        outputs:
          result: { ref: loud }
        """)
        let sut = Executor()

        // When
        let outputs = try await sut.run(spec, inputs: ["who": .string("spec")])

        // Then
        #expect(outputs["result"] == .string("hello, spec!"))
    }

    @Test("a declining condition skips the step and binds null")
    func decliningConditionSkipsStep() async throws {
        // Given
        let spec = try loader.load("""
        name: gated
        inputs:
          kind: string
        steps:
          - id: only-a
            when:
              { of: { ref: inputs.kind }, is: a }
            value: taken
        outputs:
          result: { ref: only-a }
        """)
        let sut = Executor()

        // When
        let outputs = try await sut.run(spec, inputs: ["kind": .string("b")])

        // Then — a skipped step binds null, not absence
        #expect(outputs["result"] == .null)
    }

    @Test("a recoverable failure runs the rescue path")
    func recoverableFailureRunsRescue() async throws {
        // Given
        let spec = try loader.load("""
        name: rescued
        steps:
          - id: fragile
            fail: true
            rescue:
              - id: recovery
                value: recovered
        outputs:
          result: { ref: fragile }
        """)
        let sut = Executor()

        // When
        let outputs = try await sut.run(spec)

        // Then — the last rescue step's output becomes the step output
        #expect(outputs["result"] == .string("recovered"))
    }

    @Test("the failure is a value inside the rescue, and only there")
    func rescueSeesFailurePayload() async throws {
        // Given
        let spec = try loader.load("""
        name: informed
        steps:
          - id: fragile
            fail: true
            rescue:
              - id: reason
                value: { format: "saw: ${why}", with: { why: { ref: fragile.message } } }
        outputs:
          result: { ref: fragile }
        """)
        let sut = Executor()

        // When
        let outputs = try await sut.run(spec)

        // Then — inside the rescue, `fragile` was the failure payload; after
        // it, `fragile` is the rescue's output (a string here), so the payload
        // never leaks past the rescue
        #expect(outputs["result"] == .string("saw: the world did not cooperate"))
    }

    @Test("an author mistake propagates past rescue")
    func fatalErrorBypassesRescue() async throws {
        // Given — an author mistake must not be absorbed by rescue
        let spec = try loader.load("""
        name: fatal
        steps:
          - id: broken
            fail: false
            rescue:
              - id: recovery
                value: recovered
        """)
        let sut = Executor()

        // When / Then
        await #expect(throws: TestFatalError.self) {
            try await sut.run(spec)
        }
    }

    @Test("an unrescued failure propagates")
    func unrescuedFailurePropagates() async throws {
        // Given
        let spec = try loader.load("""
        name: unrescued
        steps:
          - id: fragile
            fail: true
        """)
        let sut = Executor()

        // When / Then
        await #expect(throws: TestRecoverableFailure.self) {
            try await sut.run(spec)
        }
    }

    @Test("a reference typo is not disguised by rescue")
    func referenceTypoBypassesRescue() async throws {
        // Given — shape misuse is an author error; rescue must not disguise it
        let spec = try loader.load("""
        name: typo
        inputs:
          n: int
        steps:
          - id: fragile
            value: { format: "x=${n}", with: { n: { ref: inputs.n.field } } }
            rescue:
              - id: recovery
                value: recovered
        """)
        let sut = Executor()

        // When / Then
        await #expect(throws: ReferenceUnfit.self) {
            try await sut.run(spec, inputs: ["n": .int(1)])
        }
    }

    @Test("missing data is the world's answer, absorbed by rescue")
    func absentReferenceRescues() async throws {
        // Given — missing data is the world's answer, so rescue absorbs it
        let spec = try loader.load("""
        name: absent
        inputs:
          data: object
        steps:
          - id: fragile
            value: { ref: inputs.data.missing }
            rescue:
              - id: recovery
                value: recovered
        outputs:
          result: { ref: fragile }
        """)
        let sut = Executor()

        // When
        let outputs = try await sut.run(spec, inputs: ["data": .object([:])])

        // Then
        #expect(outputs["result"] == .string("recovered"))
    }

    @Test("drilling into a skipped step's null rescues as absence")
    func skippedStepDrillRescues() async throws {
        // Given — a skipped step binds null; drilling into it is absence
        // (the world declined), which rescue absorbs
        let spec = try loader.load("""
        name: skip-then-drill
        inputs:
          kind: string
        steps:
          - id: maybe
            when:
              { of: { ref: inputs.kind }, is: a }
            value:
              name: made
          - id: fragile
            value: { format: "name=${name}", with: { name: { ref: maybe.name } } }
            rescue:
              - id: recovery
                value: recovered
        outputs:
          result: { ref: fragile }
        """)
        let sut = Executor()

        // When
        let outputs = try await sut.run(spec, inputs: ["kind": .string("b")])

        // Then
        #expect(outputs["result"] == .string("recovered"))
    }

    @Test("abort throws carrying its rendered message")
    func abortThrowsWithMessage() async throws {
        // Given
        let spec = try loader.load("""
        name: bailing
        inputs:
          reason: string
        steps:
          - id: bail
            abort: { format: "stopped: ${reason}", with: { reason: { ref: inputs.reason } } }
        """)
        let sut = Executor()

        // When / Then — abort is the language's throw, and carries its message
        do {
            _ = try await sut.run(spec, inputs: ["reason": .string("no data")])
            Issue.record("expected Aborted")
        } catch let aborted as Aborted {
            #expect(aborted.message == "stopped: no data")
        }
    }

    @Test("abort is caught by rescue like any thrown error")
    func abortRescuesLikeThrownError() async throws {
        // Given — like a thrown error, abort is catchable
        let spec = try loader.load("""
        name: caught
        steps:
          - id: bail
            abort: giving up
            rescue:
              - id: recovery
                value: recovered
        outputs:
          result: { ref: bail }
        """)
        let sut = Executor()

        // When
        let outputs = try await sut.run(spec)

        // Then
        #expect(outputs["result"] == .string("recovered"))
    }
}
