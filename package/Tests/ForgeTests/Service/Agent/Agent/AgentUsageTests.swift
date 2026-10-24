//
//  AgentUsageTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import Forge

@Suite("AgentUsage Tests")
struct AgentUsageTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("claude dialect leaves input tokens untouched")
    func claudeDialectKeepsInputAsIs() {
        // Given
        let usage = AgentUsage(providerValues: [
                "input_tokens": 6,
                "output_tokens": 348,
                "cache_creation_input_tokens": 123_828,
                "cache_read_input_tokens": 176_855,
        ])

        // Then
        #expect(usage.inputTokens == 6)
        #expect(usage.cacheWriteTokens == 123_828)
        #expect(usage.cacheReadTokens == 176_855)
    }
    
    @Test("cache-inclusive dialect subtracts the cached share from input")
    func cacheInclusiveDialectSubtractsCachedFromInput() {
        // Given
        let usage = AgentUsage(providerValues: [
                "input_tokens": 100_000,
                "cached_input_tokens": 90_000,
                "output_tokens": 1_200,
        ])

        // Then
        #expect(usage.inputTokens == 10_000)
        #expect(usage.cacheReadTokens == 90_000)
    }
    
    @Test("prompt_tokens dialect subtracts by the same rule")
    func promptTokensDialectAlsoSubtracts() {
        // Given
        let usage = AgentUsage(providerValues: [
                "prompt_tokens": 5_000,
                "cached_input_tokens": 4_000,
                "completion_tokens": 200,
        ])

        // Then
        #expect(usage.inputTokens == 1_000)
        #expect(usage.outputTokens == 200)
    }
    
    @Test("cache exceeding input clamps at 0 instead of going negative")
    func cachedExceedingInputClampsToZeroInsteadOfGoingNegative() {
        // Given
        let usage = AgentUsage(providerValues: [
                "input_tokens": 100,
                "cached_input_tokens": 500,
        ])

        // Then
        #expect(usage.inputTokens == 0)
    }
    
    @Test("missing input stays nil even with cache present — not 0")
    func missingInputStaysNilEvenWithCacheRead() {
        // Given
        let usage = AgentUsage(providerValues: ["cached_input_tokens": 500])

        // Then
        #expect(usage.inputTokens == nil)
        #expect(usage.cacheReadTokens == 500)
    }
    
    @Test("extracts only this turn's share from the thread cumulative")
    func subtractingRecoversTurnShareFromThreadCumulative() {
        // Given
        let first = AgentUsage(
            providerValues: [
                "input_tokens": 214_262, "cached_input_tokens": 158_976, "output_tokens": 1_596,
        ])
        let second = AgentUsage(
            providerValues: [
                "input_tokens": 357_993, "cached_input_tokens": 290_816, "output_tokens": 2_364,
        ])
        let delta = second.subtracting(first)

        // Then
        #expect(delta.inputTokens == (357_993 - 290_816) - (214_262 - 158_976))
        #expect(delta.cacheReadTokens == 290_816 - 158_976)
        #expect(delta.outputTokens == 2_364 - 1_596)
    }
    
    @Test("clamps to 0 instead of negative when the cumulative goes backwards")
    func subtractingClampsNonMonotonicCumulativeToZero() {
        // Given
        let baseline = AgentUsage(inputTokens: 100, outputTokens: 10)
        let delta = AgentUsage(inputTokens: 40, outputTokens: 10).subtracting(baseline)

        // Then
        #expect(delta.inputTokens == 0)
        #expect(delta.outputTokens == 0)
    }
    
    @Test("unmeasured axes stay nil — not filled with 0")
    func subtractingKeepsUnmeasuredAxesNil() {
        // Given
        let delta = AgentUsage(outputTokens: 30).subtracting(AgentUsage(inputTokens: 5))

        // Then
        #expect(delta.inputTokens == nil)
        #expect(delta.outputTokens == 30)
    }
    
    // MARK: - Private
}
