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
    static func natives() throws -> Module {
        try Module(
            types: [
                runType: .struct(["workflow_id": .string, "root_id": .string]),
                originType: .struct(["kind": .string, "id": .optional(.string)])
            ],
            procedures: [
                "Forge.Native.shell": Procedure(
                    signature: Signature(
                        of: ShellAction.self,
                        returns: .string,
                        failing: .these([BackendNonzeroExit.type, DeadlineExceeded.type]),
                        isolation: .isolated
                    ),
                    implementation: .effect(ShellAction())
                ),
                "Forge.Native.extract": Procedure(
                    signature: Signature(
                        of: ExtractQuery.self,
                        returns: .dictionary(key: .string, value: .any),
                        constness: .const,
                        isolation: .isolated
                    ),
                    implementation: .query(ExtractQuery())
                ),
                "Forge.Native.agent": Procedure(
                    signature: Signature(of: AgentAction.self, returns: .string, isolation: .isolated),
                    implementation: .effect(AgentAction())
                ),
                "Forge.Native.invoke": Procedure(
                    signature: Signature(
                        of: InvokeAction.self,
                        returns: InvokeAction.result,
                        failing: .anything,
                        isolation: .isolated
                    ),
                    implementation: .effect(InvokeAction())
                ),
                "Forge.Native.dispatch": Procedure(
                    signature: Signature(
                        of: DispatchAction.self,
                        returns: .dictionary(key: .string, value: .any),
                        failing: .these([ChildRunFailed.type, DeadlineExceeded.type]),
                        isolation: .isolated
                    ),
                    implementation: .effect(DispatchAction())
                ),
                "Forge.Native.resource": Procedure(
                    signature: Signature(of: ResourceAction.self, returns: .string, isolation: .isolated),
                    implementation: .effect(ResourceAction())
                ),
                "Forge.Native.locate": Procedure(
                    signature: Signature(of: LocateAction.self, returns: .string, isolation: .isolated),
                    implementation: .effect(LocateAction())
                ),
                "Forge.Native.run": Procedure(
                    signature: Signature(of: RunAction.self, returns: .named(runType), isolation: .isolated),
                    implementation: .effect(RunAction())
                ),
                "Forge.Native.origin": Procedure(
                    signature: Signature(of: OriginAction.self, returns: .named(originType), isolation: .isolated),
                    implementation: .effect(OriginAction())
                )
            ]
        )
    }

    // What every link holds beside the workflows: forge's verbs and the
    // standard vocabulary.
    static func linkables() throws -> [Module] {
        [try natives()] + Module.standard
    }

    // The one front end forge reads a workflow with.
    static func frontend() -> YAMLFrontend {
        YAMLFrontend()
    }

    // MARK: - Private
}
