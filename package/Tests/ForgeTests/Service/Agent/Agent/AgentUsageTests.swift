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
    @Test("extracts only this turn's share from the thread cumulative")
    func subtractingRecoversTurnShareFromThreadCumulative() {
        // Given
        let first = AgentUsage(inputTokens: 214_262 - 158_976, outputTokens: 1_596, cacheReadTokens: 158_976)
        let second = AgentUsage(inputTokens: 357_993 - 290_816, outputTokens: 2_364, cacheReadTokens: 290_816)
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
