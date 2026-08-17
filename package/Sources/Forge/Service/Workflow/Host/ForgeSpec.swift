//
//  ForgeSpec.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp
import WarpIR

enum ForgeSpec {
    // MARK: - Property
    // What forge's verbs answer to. A module like any other — the standard
    // vocabulary is one too, and the linker is handed both beside the workflow's
    // own declarations. What used to be a `Library` installed into the language
    // is this: a declaration is a declaration, whoever wrote it.
    static let vocabulary = Module(
        name: "forge",
        description: "The verbs forge reaches the world with.",
        procedures: [
            "shell": Procedure(
                signature: Signature(
                    parameters: [
                        "command": Parameter(type: .array(.any)),
                        "cwd": Parameter(type: .string, default: .null),
                        "env": Parameter(type: .object(.any), default: .null),
                        "stdin": Parameter(type: .string, default: .null),
                        "outputs": Parameter(type: .object(.any), default: .null),
                        "timeout": Parameter(type: .double, default: .null)
                    ]
                ),
                implementation: .effect(ShellAction())
            ),
            "agent": Procedure(
                signature: Signature(parameters: ["prompt": Parameter(type: .string)]),
                implementation: .effect(AgentAction())
            ),
            "invoke": Procedure(
                signature: Signature(
                    parameters: [
                        "model": Parameter(type: .string, default: .null),
                        "allowed": Parameter(type: .any, default: .null),
                        "env_extra": Parameter(type: .object(.any), default: .null),
                        "cwd": Parameter(type: .string, default: .null),
                        "permission_mode": Parameter(type: .string, default: .null),
                        "share_session": Parameter(type: .bool, default: .null),
                        "timeout": Parameter(type: .double, default: .null)
                    ]
                ),
                implementation: .effect(InvokeAction())
            ),
            "dispatch": Procedure(
                signature: Signature(
                    parameters: [
                        "name": Parameter(type: .string, default: .null),
                        "spec": Parameter(type: .object(.any), default: .null),
                        "inputs": Parameter(type: .object(.any), default: .null),
                        "timeout": Parameter(type: .double, default: .null)
                    ]
                ),
                implementation: .effect(DispatchAction())
            ),
            "dynamic": Procedure(
                signature: Signature(parameters: ["compose": Parameter(type: .array(.any))]),
                implementation: .effect(DynamicAction())
            ),
            "resource": Procedure(
                signature: Signature(
                    parameters: [
                        "content": Parameter(type: .string, default: .null),
                        "path": Parameter(type: .string, default: .null),
                        "inputs": Parameter(type: .object(.any), default: .null)
                    ]
                ),
                implementation: .effect(ResourceAction())
            )
        ]
    )

    // The two names the daemon supplies to every run. They were an ambient tier
    // the language carried for us; the language has one tier now, so they are
    // declared like everything else — added to each procedure a workflow
    // declares, with a default, so a workflow that never mentions them is still
    // a workflow and one that does is reading a name it can see.
    static let ambient = ["origin", "run"]

    // A verb named the way the link will know it. A form spells a word, and the
    // module that answers it is forge's — saying so is what keeps a workflow
    // that happens to declare `agent` from shadowing the verb inside itself.
    static func selector(_ word: String) -> String {
        "\(vocabulary.name ?? "").\(word)"
    }

    // What every link needs beside the workflows themselves. These used to be
    // installed into the language, so a link got them without asking.
    static let linkables: [Module] = [vocabulary, .standard]

    // MARK: - Initializer
    // MARK: - Public
    // Every procedure in a workflow document gets the ambient names, so a run can
    // hand them over as ordinary arguments.
    static func seeding(_ module: Module) -> Module {
        Module(
            name: module.name,
            description: module.description,
            types: module.types,
            constants: module.constants,
            procedures: module.procedures.mapValues { procedure in
                var parameters = procedure.signature.parameters

                for name in ambient where parameters[name] == nil {
                    parameters[name] = Parameter(type: .any, default: .null)
                }

                return Procedure(
                    description: procedure.description,
                    signature: Signature(
                        receiver: procedure.signature.receiver,
                        parameters: parameters,
                        answer: procedure.signature.answer
                    ),
                    implementation: procedure.implementation
                )
            }
        )
    }

    // The one loader forge configures — kernel flow plus the words forge spells
    // its verbs with.
    static func loader() -> Loader {
        let registry: ConstructRegistry

        do {
            registry = try ConstructRegistry.standard
                // The kernel spells a call on a procedure value `invoke`, and
                // forge has spent that word on a verb of its own since before the
                // kernel had one. A spelling belongs to the table, so forge takes
                // the word back here rather than the language giving it up.
                .removing(InvokeForm.key)
                .registering(ShellActionForm.self)
                .registering(AgentActionForm.self)
                .registering(InvokeActionForm.self)
                .registering(DispatchActionForm.self)
                .registering(DynamicActionForm.self)
                .registering(ResourceActionForm.self)
        } catch {
            preconditionFailure("forge action keys collide with the kernel: \(error)")
        }

        return Loader(registry: registry)
    }

    // MARK: - Private
}
