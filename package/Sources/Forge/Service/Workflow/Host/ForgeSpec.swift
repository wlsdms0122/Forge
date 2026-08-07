//
//  ForgeSpec.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

enum ForgeSpec {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    // The one loader forge configures — kernel flow plus forge's verbs, with the
    // daemon-injected namespaces declared so specs can reference them at load.
    static func loader() -> SpecLoader {
        let registry: ActionRegistry

        do {
            registry = try ActionRegistry.standard
                .registering(ShellAction.self)
                .registering(AgentAction.self)
                .registering(InvokeAction.self)
                .registering(DispatchAction.self)
                .registering(DynamicAction.self)
                .registering(ResourceAction.self)
        } catch {
            preconditionFailure("forge action keys collide with the kernel: \(error)")
        }

        return SpecLoader(
            registry: registry,
            library: .standard,
            contextHeads: ["origin", "run"]
        )
    }

    // MARK: - Private
}

