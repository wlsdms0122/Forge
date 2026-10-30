//
//  ChatFinishReason.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

enum ChatFinishReason: Sendable, Equatable {
    case stop
    case toolCalls
    case length
    case contentFilter
    case unspecified
    case other(String)

    // MARK: - Property
    var rawValue: String? {
        switch self {
        case .stop:
            return "stop"

        case .toolCalls:
            return "tool_calls"

        case .length:
            return "length"

        case .contentFilter:
            return "content_filter"

        case .unspecified:
            return nil

        case .other(let raw):
            return raw
        }
    }

    var completesTurn: Bool {
        switch self {
        case .stop, .toolCalls, .unspecified:
            return true

        case .length, .contentFilter, .other:
            return false
        }
    }

    // MARK: - Initializer
    init(rawValue: String?) {
        switch rawValue {
        case .none:
            self = .unspecified

        case "stop":
            self = .stop

        case "tool_calls":
            self = .toolCalls

        case "length":
            self = .length

        case "content_filter":
            self = .contentFilter

        case .some(let raw):
            self = .other(raw)
        }
    }

    // MARK: - Public
    // MARK: - Private
}
