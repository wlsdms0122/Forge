//
//  LiveAgentTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Testing
import Warp
@testable import Forge

@Suite("LiveAgent Tests")
struct LiveAgentTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("withSession opens a session bound to the task, and send speaks through it")
    func sendSpeaksThroughAmbientSession() async throws {
        // Given
        let recorder = AgentRecorder()
        let sut = LiveAgent(executor: AgentExecutor(backend: recorder))
        let settings = AgentSessionSettings(model: "claude:probe")

        // When
        let reply = try await sut.withSession(settings) {
            .string(try await sut.send(prompt: "hello"))
        }

        // Then
        #expect(reply == .string("echo:hello"))
        #expect(recorder.invocations.elements.first?.agent.model?.displayName == "claude:probe")
    }

    @Test("send without a session throws as an author error")
    func sendThrowsWithoutSession() async throws {
        // Given
        let sut = LiveAgent(executor: AgentExecutor(backend: StubBackend()))

        // When / Then
        await #expect(throws: AgentSessionMissing.self) {
            _ = try await sut.send(prompt: "hello")
        }
    }

    @Test("share_session reuses the outer session")
    func shareSessionReusesAmbientSession() async throws {
        // Given
        let recorder = AgentRecorder()
        let sut = LiveAgent(executor: AgentExecutor(backend: recorder))
        let outer = AgentSessionSettings(model: "claude:outer")
        let inner = AgentSessionSettings(shareSession: true)

        // When
        _ = try await sut.withSession(outer) {
            try await sut.withSession(inner) {
                .string(try await sut.send(prompt: "inner"))
            }
        }

        // Then
        #expect(recorder.invocations.elements.first?.agent.model?.displayName == "claude:outer")
    }

    @Test("share_session without an outer session opens a new one from the carried config")
    func shareSessionOpensNewSessionWithoutAmbient() async throws {
        // Given — share_session is conditional joining, so it carries a config for the
        // case where joining fails. Without an ambient session, that config is used.
        let recorder = AgentRecorder()
        let sut = LiveAgent(executor: AgentExecutor(backend: recorder))
        let settings = AgentSessionSettings(model: "claude:fallback", shareSession: true)

        // When
        let reply = try await sut.withSession(settings) {
            .string(try await sut.send(prompt: "solo"))
        }

        // Then
        #expect(reply == .string("echo:solo"))
        #expect(recorder.invocations.elements.first?.agent.model?.displayName == "claude:fallback")
    }

    @Test("invoke without a model runs on the one registered backend")
    func noModelRunsOnTheSoleBackend() async throws {
        // Given
        let recorder = AgentRecorder()
        let sut = LiveAgent(executor: AgentExecutor(backend: recorder))
        let settings = AgentSessionSettings()

        // When
        let reply = try await sut.withSession(settings) {
            .string(try await sut.send(prompt: "hello"))
        }

        // Then
        let invocation = try #require(recorder.invocations.elements.first)

        #expect(reply == .string("echo:hello"))
        #expect(invocation.agent.model == nil)
    }

    @Test("invoke without a model is refused with the registry's reason when more than one backend is registered")
    func noModelIsRefusedAmongBackends() async throws {
        // Given
        let registry = BackendRegistry(["claude": StubBackend(), "codex": StubBackend()])
        let sut = LiveAgent(executor: AgentExecutor(backends: registry))
        let settings = AgentSessionSettings()
        let reason = #expect(throws: BackendNotRegistered.self) {
            try registry.resolve(provider: nil)
        }

        // When
        let refusal = await #expect(throws: BackendNotRegistered.self) {
            _ = try await sut.withSession(settings) { .null }
        }

        // Then
        #expect(refusal?.message == (try #require(reason)).message)
    }

    @Test("an invalid permission_mode throws")
    func unknownPermissionModeThrows() async throws {
        // Given
        let sut = LiveAgent(executor: AgentExecutor(backend: StubBackend()))
        let settings = AgentSessionSettings(model: "claude", permissionMode: "yolo")

        // When / Then
        await #expect(throws: AgentValidationError.self) {
            _ = try await sut.withSession(settings) { .null }
        }
    }
}
