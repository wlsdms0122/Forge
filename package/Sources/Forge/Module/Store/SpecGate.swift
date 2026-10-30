//
//  SpecGate.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum SpecGate {
    private struct AnyKey: CodingKey {
        // MARK: - Property
        let stringValue: String
        
        var intValue: Int? { nil }
        
        // MARK: - Initializer
        init?(stringValue: String) {
            self.stringValue = stringValue
        }
        
        init?(intValue: Int) {
            nil
        }
        
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func rejectUnknownKeys<K: CodingKey & CaseIterable>(
        in decoder: Decoder,
        known: K.Type,
        extra: [String] = [],
        context: String
    ) throws {
        try rejectUnknownKeys(
            in: decoder,
            known: K.allCases.map(\.stringValue) + extra,
            context: context
        )
    }
    
    static func rejectUnknownKeys(
        in decoder: Decoder,
        known: [String],
        context: String
    ) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        let unknown = container.allKeys
            .map(\.stringValue)
            .filter { key in !known.contains(key) }
        
        guard unknown.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "\(context): unknown key(s) \(unknown.sorted().joined(separator: ", "))"
                        + " — known keys: \(known.sorted().joined(separator: ", "))"
                )
            )
        }
    }
    
    // MARK: - Private
}
