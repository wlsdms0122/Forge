//
//  AgentUsage.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct AgentUsage: Sendable, Equatable {
    // MARK: - Property
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheWriteTokens: Int?
    let cacheReadTokens: Int?
    let reasoningOutputTokens: Int?
    
    var isEmpty: Bool {
        inputTokens == nil
            && outputTokens == nil
            && cacheWriteTokens == nil
            && cacheReadTokens == nil
            && reasoningOutputTokens == nil
    }
    
    var asDictionary: [String: Int] {
        var values: [String: Int] = [:]
        
        if let inputTokens { values["input_tokens"] = inputTokens }
        if let outputTokens { values["output_tokens"] = outputTokens }
        if let cacheWriteTokens { values["cache_write_tokens"] = cacheWriteTokens }
        if let cacheReadTokens { values["cache_read_tokens"] = cacheReadTokens }
        if let reasoningOutputTokens { values["reasoning_output_tokens"] = reasoningOutputTokens }
        
        return values
    }
    
    // MARK: - Initializer
    init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheWriteTokens: Int? = nil,
        cacheReadTokens: Int? = nil,
        reasoningOutputTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.cacheReadTokens = cacheReadTokens
        self.reasoningOutputTokens = reasoningOutputTokens
    }
    
    init(providerValues: [String: Int]) {
        let cacheRead = providerValues["cache_read_input_tokens"]
            ?? providerValues["cached_input_tokens"]
        
        var input = providerValues["input_tokens"] ?? providerValues["prompt_tokens"]
        
        if
            providerValues["cached_input_tokens"] != nil,
            let total = input,
            let cached = cacheRead
        {
            input = max(0, total - cached)
        }
        
        self.init(
            inputTokens: input,
            outputTokens: providerValues["output_tokens"] ?? providerValues["completion_tokens"],
            cacheWriteTokens: providerValues["cache_creation_input_tokens"]
                ?? providerValues["cache_write_input_tokens"],
            cacheReadTokens: cacheRead,
            reasoningOutputTokens: providerValues["reasoning_output_tokens"]
        )
    }
    
    // MARK: - Public
    subscript(key: String) -> Int? { asDictionary[key] }
    
    func adding(_ other: AgentUsage) -> AgentUsage {
        AgentUsage(
            inputTokens: Self.sum(inputTokens, other.inputTokens),
            outputTokens: Self.sum(outputTokens, other.outputTokens),
            cacheWriteTokens: Self.sum(cacheWriteTokens, other.cacheWriteTokens),
            cacheReadTokens: Self.sum(cacheReadTokens, other.cacheReadTokens),
            reasoningOutputTokens: Self.sum(
                reasoningOutputTokens,
                other.reasoningOutputTokens
            )
        )
    }
    
    func subtracting(_ baseline: AgentUsage) -> AgentUsage {
        AgentUsage(
            inputTokens: Self.difference(inputTokens, baseline.inputTokens),
            outputTokens: Self.difference(outputTokens, baseline.outputTokens),
            cacheWriteTokens: Self.difference(cacheWriteTokens, baseline.cacheWriteTokens),
            cacheReadTokens: Self.difference(cacheReadTokens, baseline.cacheReadTokens),
            reasoningOutputTokens: Self.difference(
                reasoningOutputTokens,
                baseline.reasoningOutputTokens
            )
        )
    }
    
    // MARK: - Private
    private static func sum(_ left: Int?, _ right: Int?) -> Int? {
        guard left != nil || right != nil else { return nil }
        
        return (left ?? 0) + (right ?? 0)
    }
    
    private static func difference(_ total: Int?, _ baseline: Int?) -> Int? {
        guard let total else { return nil }
        
        return max(0, total - (baseline ?? 0))
    }
}
