//
//  DynamicAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp
import WarpIR

// Steps that arrived as data — `compose` resolves to step objects (typically
// carried through a signature, as in bot-invoke) and the language's runtime
// lowering door turns them into IR through the same decoder and registry the
// load path uses. No text is re-parsed.
struct DynamicAction: Warp.Effect {
    // MARK: - Property


    // MARK: - Initializer
    // MARK: - Public
    func run(_ invocation: Warp.Invocation) async throws -> Warp.Value {
        let environment = try ForgeEnvironment.from(invocation)
        let resolver = invocation.resolver
        let output = invocation.block("output")?.block.result

        guard case .array(let compose) = try invocation.resolve("compose"), !compose.isEmpty else {
            throw ExecutionError("dynamic.compose is empty")
        }

        var lowered: [Warp.Statement] = []

        for value in compose {
            // A part may carry one step or a batch of them — flatten so authors
            // can splice `{ ref: steps }` next to literal steps.
            switch value {
            case .array:
                lowered += try environment.loader.statements(from: value)

            case .object:
                lowered.append(try environment.loader.statement(from: value))

            default:
                throw ExecutionError(
                    "dynamic.compose part resolved to \(value.type)"
                        + " — expected a step object or an array of them"
                )
            }
        }

        // The fragment is a quoted procedure. Its references close over the
        // fragment's own step ids plus the run/origin contexts — never the
        // ambient scope: caller values arrive embedded in the step data, and a
        // name that would read the enclosing spec's bindings is a load error
        // here, not a dynamic lookup.
        let ambient = invocation.scope
        let reserved = Set(ForgeSpec.ambient)
        let fragmentScope = Warp.Scope(
            bindings: ambient.bindings.filter { name, _ in reserved.contains(name) }
        )

        // Shadowing an ordinary name is legal in this language, and since the
        // run's identity became ordinary parameters it would be legal here too —
        // a lowered step could bind `run` and every step after it would read the
        // fragment's value instead of the run's. That is forge's to refuse, at
        // forge's layer, because forge is what put those names there.
        if let claimed = lowered.first(where: { statement in
            reserved.contains(statement.id)
        }) {
            throw ExecutionError(
                "dynamic step '\(claimed.id)' claims a name the run supplies"
                    + " (\(ForgeSpec.ambient.sorted().joined(separator: ", ")))"
            )
        }

        do {
            try Warp.Validator().validate(body: lowered, visible: reserved)
        } catch {
            throw ExecutionError("dynamic steps failed validation: \(error)")
        }

        // `output` is authored in the enclosing spec, so it sees the ambient
        // scope plus the fragment's step results — and its references are
        // gated here, before the fragment's side effects run, since the load
        // validator cannot know the fragment's ids.
        if let output {
            let visible = reserved
                .union(ambient.bindings.keys)
                .union(lowered.map(\.id))

            do {
                try Warp.Validator().validate(output, visible: visible)
            } catch {
                throw ExecutionError(
                    "dynamic.output names nothing visible here — neither an"
                        + " enclosing binding nor a lowered step id: \(error)"
                )
            }
        }

        let result = try await invocation.run(lowered, in: fragmentScope)

        guard let output else { return result.lastResult }

        var outputScope = ambient

        for (id, value) in result.scope.bindings {
            outputScope = outputScope.binding(id, to: value)
        }

        return try invocation.resolver(for: outputScope).resolve(output)
    }

    // MARK: - Private
}
