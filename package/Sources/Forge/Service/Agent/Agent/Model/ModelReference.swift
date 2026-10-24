//
//  ModelReference.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ModelReference: Sendable, Equatable {
    // MARK: - Property
    let provider: String
    let model: String

    var isBackendDefault: Bool { model.isEmpty }

    var specifiedModel: String? { isBackendDefault ? nil : model }

    var displayName: String { isBackendDefault ? "\(provider):default" : "\(provider):\(model)" }

    // MARK: - Initializer
    init(provider: String, model: String) throws {
        guard !provider.isEmpty, !provider.contains(":") else {
            throw ProtocolError(
                "invoke: model provider must be non-empty and cannot contain ':',"
                    + " got '\(provider)'"
            )
        }

        guard model != "auto" else {
            throw ProtocolError(
                "invoke: omit the model and colon to use the backend default;"
                    + " ':auto' is not a model"
            )
        }

        self.provider = provider
        self.model = model
    }

    init(_ reference: String) throws {
        let separator = reference.firstIndex(of: ":")
        let provider = separator.map { index in String(reference[..<index]) } ?? reference

        if let separator, reference.index(after: separator) == reference.endIndex {
            throw ProtocolError(
                "invoke: model must specify a model after the colon or omit the colon to use"
                    + " the backend default, got '\(reference)'"
            )
        }

        let model = separator.map { index in
            String(reference[reference.index(after: index)...])
        } ?? ""

        try self.init(provider: provider, model: model)
    }

    // MARK: - Public
    func replacingModel(with translatedModel: String?) throws -> ModelReference {
        try ModelReference(provider: provider, model: translatedModel ?? "")
    }

    // MARK: - Private
}
