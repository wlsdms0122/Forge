//
//  ToolEvent.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ToolEvent: Sendable, Equatable {
    // MARK: - Property
    var id: String?
    var name: String?
    var input: String?
    var resultPreview: String
    var isError: Bool
    var startedAt: Date?
    var completedAt: Date?

    var durationMs: Int? {
        guard let startedAt, let completedAt else { return nil }

        return Int((completedAt.timeIntervalSince(startedAt) * 1000).rounded())
    }

    // MARK: - Initializer
    init(
        id: String? = nil,
        name: String? = nil,
        input: String? = nil,
        resultPreview: String = "",
        isError: Bool = false,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.input = input
        self.resultPreview = resultPreview
        self.isError = isError
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    // MARK: - Public
    // MARK: - Private
}
