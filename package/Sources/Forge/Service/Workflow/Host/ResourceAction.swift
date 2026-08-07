//
//  ResourceAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

// Asks the resource root one of two questions, named by what the step gets
// back. `content` reads the file and renders it as a template over the given
// inputs. `path` resolves the file's absolute location without ever reading
// it — the form for handing a script to `shell`, where rendering would be
// wrong twice over: a script's own `$` syntax is not template dialect, and an
// executable wants to be run, not inlined.
struct ResourceAction: Spec.Action {
    enum Ask: Sendable {
        case content(Spec.Reference, inputs: [String: Spec.Reference])
        case path(Spec.Reference)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case content
        case path
        case inputs
    }

    // MARK: - Property
    static let key = "resource"

    let ask: Ask

    var referencedPaths: [[PathSegment]] {
        switch ask {
        case .content(let file, let inputs):
            return file.referencedPaths + inputs.values.flatMap(\.referencedPaths)

        case .path(let file):
            return file.referencedPaths
        }
    }

    // MARK: - Initializer
    init(ask: Ask) {
        self.ask = ask
    }

    init(from decoder: Decoder) throws {
        try Spec.KeyGate.rejectUnknownKeys(
            in: decoder,
            known: CodingKeys.self,
            context: "resource"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch (container.contains(.content), container.contains(.path)) {
        case (true, false):
            self.ask = .content(
                try container.decode(Spec.Reference.self, forKey: .content),
                inputs: try container.decodeIfPresent(
                    [String: Spec.Reference].self,
                    forKey: .inputs
                ) ?? [:]
            )

        case (false, true):
            guard !container.contains(.inputs) else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: container.codingPath,
                        debugDescription: "resource `path` answers a location —"
                            + " `inputs` only accompany `content`, which renders"
                    )
                )
            }

            self.ask = .path(try container.decode(Spec.Reference.self, forKey: .path))

        case (true, true), (false, false):
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "resource asks exactly one of `content`"
                        + " (render the file) or `path` (locate the file)"
                )
            )
        }
    }

    // MARK: - Public
    func run(_ context: ActionContext) async throws -> Spec.Value {
        let host = try ForgeHost.from(context)
        let resolver = context.resolver

        switch ask {
        case .content(let file, let inputs):
            let rendered = try await Self.render(
                relative: try resolver.string(file),
                inputs: try inputs.mapValues { reference in
                    try resolver.resolve(reference)
                },
                resources: host.resources,
                library: resolver.library
            )

            return .string(rendered)

        case .path(let file):
            return .string(try await host.resources.locate(try resolver.string(file)))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch ask {
        case .content(let file, let inputs):
            try container.encode(file, forKey: .content)

            if !inputs.isEmpty { try container.encode(inputs, forKey: .inputs) }

        case .path(let file):
            try container.encode(file, forKey: .path)
        }
    }

    // MARK: - Private
    private static func render(
        relative: String,
        inputs: [String: Spec.Value],
        resources: any ResourceReading,
        library: SpecLibrary
    ) async throws -> String {
        let body = try await resources.read(relative)

        // The resource body is a template over the given inputs — the kernel
        // parses it and renders it against a scope holding nothing but those
        // inputs, the same closed surface `{ format: }` uses.
        let segments = try Spec.TemplateParser().parse(body)

        return try Spec.Resolver.render(
            segments,
            scope: .closed(bindings: inputs, library: library)
        )
    }

}
