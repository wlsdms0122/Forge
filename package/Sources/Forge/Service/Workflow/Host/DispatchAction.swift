//
//  DispatchAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

// Asks the daemon for an isolated run — a host act with its own lifetime, ACL
// and slot, not a language call. `use` is the function call; this is
// Process.run. Exactly one of `name` (catalog) or `spec` (inline) names the
// target; the daemon settles inputs against the target's signature.
struct DispatchAction: Spec.Action {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case name
        case spec
        case inputs
        case timeout
    }

    // MARK: - Property
    static let key = "dispatch"

    let name: Spec.Reference?
    let inline: Spec.Value?
    let inputs: [String: Spec.Reference]
    let timeout: Double?

    var referencedPaths: [[PathSegment]] {
        (name?.referencedPaths ?? []) + inputs.values.flatMap(\.referencedPaths)
    }

    // MARK: - Initializer
    // The invariants live on the one designated initializer — however a value is
    // constructed, decoded or programmatic, the same rules hold.
    init(
        name: Spec.Reference? = nil,
        inline: Spec.Value? = nil,
        inputs: [String: Spec.Reference] = [:],
        timeout: Double? = nil
    ) throws {
        switch (name, inline) {
        case (nil, nil), (.some, .some):
            throw ValidationError("dispatch must declare exactly one of `name` or `spec`")

        default:
            break
        }

        self.name = name
        self.inline = inline
        self.inputs = inputs
        self.timeout = timeout
    }

    init(from decoder: Decoder) throws {
        try Spec.KeyGate.rejectUnknownKeys(
            in: decoder,
            known: CodingKeys.self,
            context: "dispatch"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)

        do {
            try self.init(
                name: try container.decodeIfPresent(Spec.Reference.self, forKey: .name),
                inline: try container.decodeIfPresent(Spec.Value.self, forKey: .spec),
                inputs: try container.decodeIfPresent(
                    [String: Spec.Reference].self,
                    forKey: .inputs
                ) ?? [:],
                timeout: try container.decodeIfPresent(Double.self, forKey: .timeout)
            )
        } catch let error as ValidationError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: container.codingPath, debugDescription: "\(error)")
            )
        }

        // The inline body lowers through the loader this file is being decoded
        // with — same registry, same vocabulary, same validation — so a
        // malformed inline target fails the load, not the run.
        if let inline {
            guard let loader = decoder.userInfo[.specLoader] as? SpecLoader else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: container.codingPath,
                        debugDescription: "dispatch inline spec requires the configuring"
                            + " SpecLoader"
                    )
                )
            }

            do {
                _ = try loader.lower(inline)
            } catch {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: container.codingPath, debugDescription: "\(error)")
                )
            }
        }
    }

    // MARK: - Public
    func run(_ context: ActionContext) async throws -> Spec.Value {
        let host = try ForgeHost.from(context)
        let resolver = context.resolver
        let target = try name.map { reference in try resolver.string(reference) }
        let settled = try inputs.mapValues { reference in try resolver.resolve(reference) }
        let inline = self.inline

        return try await withHostDeadline(seconds: timeout) {
            try await host.dispatcher.dispatch(
                name: target,
                inline: inline,
                inputs: settled
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(inline, forKey: .spec)

        if !inputs.isEmpty { try container.encode(inputs, forKey: .inputs) }

        try container.encodeIfPresent(timeout, forKey: .timeout)
    }

    // MARK: - Private
}
