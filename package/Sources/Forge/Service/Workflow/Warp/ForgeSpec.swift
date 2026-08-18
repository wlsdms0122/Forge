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
    // Every procedure in a workflow document gets the ambient names, declared
    // in the document itself rather than added to the module afterwards:
    // loading validates, so a name added after the load is a name validation
    // never saw, and a file reading `run.workflow_id` would be refused by the
    // very check that is supposed to tell an author it is fine.
    static func seeding(document value: Value) -> Value {
        guard case let .object(document) = value else { return value }
        guard case let .object(procedures)? = document["procedures"] else {
            return .object(document)
        }

        var seeded = document

        seeded["procedures"] = .object(procedures.mapValues(seeding(procedure:)))

        return .object(seeded)
    }

    // One procedure, for the doors that carry one rather than a document.
    static func seeding(procedure value: Value) -> Value {
        guard case let .object(procedure) = value else { return value }

        var declared: [String: Value]

        if case let .object(written)? = procedure["parameters"] {
            declared = written
        } else {
            declared = [:]
        }

        for name in ambient where declared[name] == nil {
            declared[name] = .object(["type": .string("any"), "default": .null])
        }

        var seeded = procedure

        seeded["parameters"] = .object(declared)

        return .object(seeded)
    }

    // The one loader forge configures — the language's constructs plus the words
    // forge spells its verbs with.
    static func loader() -> Loader {
        let registry: ConstructRegistry

        do {
            registry = try ConstructRegistry.standard
                // The language spells a call on a procedure value `invoke`, and
                // forge has spent that word on a verb of its own. A spelling
                // belongs to the table, so forge takes the word back here rather
                // than the language giving it up.
                .removing(InvokeForm.key)
                .registering(ShellActionForm.self)
                .registering(AgentActionForm.self)
                .registering(InvokeActionForm.self)
                .registering(DispatchActionForm.self)
                .registering(DynamicActionForm.self)
                .registering(ResourceActionForm.self)
        } catch {
            preconditionFailure("forge action keys collide with the language: \(error)")
        }

        return Loader(registry: registry)
    }

    // MARK: - Private
}
