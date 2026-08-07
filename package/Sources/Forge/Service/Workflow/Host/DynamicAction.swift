//
//  DynamicAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

// Steps that arrived as data — `compose` resolves to step objects (typically
// carried through a signature, as in bot-invoke) and the kernel's runtime
// lowering door turns them into IR through the same decoder and registry the
// load path uses. No text is re-parsed.
struct DynamicAction: Spec.Action {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case compose
        case output
    }

    // MARK: - Property
    static let key = "dynamic"

    let compose: [Spec.Reference]
    let output: Spec.Reference?

    var referencedPaths: [[PathSegment]] {
        compose.flatMap(\.referencedPaths)
    }

    // MARK: - Initializer
    init(compose: [Spec.Reference], output: Spec.Reference? = nil) {
        self.compose = compose
        self.output = output
    }

    init(from decoder: Decoder) throws {
        try Spec.KeyGate.rejectUnknownKeys(
            in: decoder,
            known: CodingKeys.self,
            context: "dynamic"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.compose = try container.decode([Spec.Reference].self, forKey: .compose)
        self.output = try container.decodeIfPresent(Spec.Reference.self, forKey: .output)

        guard !compose.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "dynamic.compose is empty"
                )
            )
        }
    }

    // MARK: - Public
    func run(_ context: ActionContext) async throws -> Spec.Value {
        let host = try ForgeHost.from(context)
        let resolver = context.resolver
        var lowered: [Spec.Step] = []

        for part in compose {
            let value = try resolver.resolve(part)

            // A part may carry one step or a batch of them — flatten so authors
            // can splice `{ ref: inputs.steps }` next to literal steps.
            switch value {
            case .array:
                lowered += try host.loader.decode([Spec.Step].self, from: value)

            case .object:
                lowered.append(try host.loader.decode(Spec.Step.self, from: value))

            default:
                throw ExecutionError(
                    "dynamic.compose part resolved to \(value.typeName)"
                        + " — expected a step object or an array of them"
                )
            }
        }

        // The fragment is a quoted program. Its references close over the
        // fragment's own step ids plus the run/origin contexts — never the
        // ambient scope: caller values arrive embedded in the step data, and a
        // name that would read the enclosing spec's bindings is a load error
        // here, not a dynamic lookup.
        let ambient = context.scope
        let reserved = host.loader.contextHeads.union(ambient.contexts.keys)
        let fragmentScope = Spec.Scope(
            contexts: ambient.contexts,
            library: resolver.library
        )

        do {
            try Spec.Validator(contextHeads: reserved)
                .validate(steps: lowered, visible: reserved)
        } catch {
            throw ExecutionError("dynamic steps failed validation: \(error)")
        }

        // `output` is authored in the enclosing spec, so it sees the ambient
        // scope plus the fragment's step results — and its references are
        // gated here, before the fragment's side effects run, since the load
        // validator cannot know the fragment's ids.
        if let output {
            let visible = ambient.reservedHeads
                .union(reserved)
                .union(ambient.bindings.keys)
                .union(lowered.map(\.id))

            for path in output.referencedPaths {
                guard let head = path.head, visible.contains(head) else {
                    throw ExecutionError(
                        "dynamic.output reference { ref: \(path.rendered) } names"
                            + " nothing visible here — neither an enclosing binding"
                            + " nor a lowered step id"
                    )
                }
            }
        }

        let result = try await context.run(lowered, in: fragmentScope)

        guard let output else { return result.lastOutput }

        var outputScope = ambient

        for (id, value) in result.scope.bindings {
            outputScope = outputScope.binding(id, to: value)
        }

        return try context.resolver(for: outputScope).resolve(output)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(compose, forKey: .compose)
        try container.encodeIfPresent(output, forKey: .output)
    }

    // MARK: - Private
}
