//
//  ForgeSpec.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp
import WarpStandard
import WarpYAML

enum ForgeSpec {
    // MARK: - Property
    // The structs forge's verbs return.
    static let runType: Name = "Forge.Run"
    static let originType: Name = "Forge.Origin"

    // MARK: - Initializer
    // MARK: - Public
    // The verbs forge reaches the world with, as native procedures. Each one
    // runs outside the program, may run beside another, and says what it fails
    // with.
    static func vocabulary() throws -> Module {
        try Module(
            types: [
                runType: .struct(["workflow_id": .string, "root_id": .string]),
                originType: .struct(["kind": .string, "id": .nullable(.string)])
            ],
            procedures: [
                "Forge.shell": Procedure(
                    signature: Signature(
                        of: ShellAction.self,
                        returns: .any,
                        failing: .these([BackendNonzeroExit.type, DeadlineExceeded.type]),
                        isolation: .isolated
                    ),
                    implementation: .effect(ShellAction())
                ),
                "Forge.agent": Procedure(
                    signature: Signature(of: AgentAction.self, returns: .string, isolation: .isolated),
                    implementation: .effect(AgentAction())
                ),
                "Forge.invoke": Procedure(
                    signature: Signature(
                        of: InvokeAction.self,
                        returns: InvokeAction.result,
                        failing: .anything,
                        isolation: .isolated
                    ),
                    implementation: .effect(InvokeAction())
                ),
                "Forge.dispatch": Procedure(
                    signature: Signature(
                        of: DispatchAction.self,
                        returns: .dictionary(key: .string, value: .any),
                        failing: .these([ChildRunFailed.type, DeadlineExceeded.type]),
                        isolation: .isolated
                    ),
                    implementation: .effect(DispatchAction())
                ),
                "Forge.resource": Procedure(
                    signature: Signature(of: ResourceAction.self, returns: .string, isolation: .isolated),
                    implementation: .effect(ResourceAction())
                ),
                "Forge.locate": Procedure(
                    signature: Signature(of: LocateAction.self, returns: .string, isolation: .isolated),
                    implementation: .effect(LocateAction())
                ),
                "Forge.run": Procedure(
                    signature: Signature(of: RunAction.self, returns: .named(runType), isolation: .isolated),
                    implementation: .effect(RunAction())
                ),
                "Forge.origin": Procedure(
                    signature: Signature(of: OriginAction.self, returns: .named(originType), isolation: .isolated),
                    implementation: .effect(OriginAction())
                )
            ]
        )
    }

    // What every link holds beside the workflows: forge's verbs and the
    // standard vocabulary.
    static func linkables() throws -> [Module] {
        [try vocabulary()] + Module.standard
    }

    // The one front end forge reads a workflow with.
    static func frontend() throws -> YAMLFrontend {
        try YAMLFrontend()
    }

    // MARK: - Private
}
