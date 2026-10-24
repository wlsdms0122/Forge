//
//  ForgeVocabulary.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp
import WarpStandard
import WarpSyntax
import WarpYAML

// What Forge lends a workflow: the library document the binary carries,
// written in the YAML notation over the native verbs, the natives, and the
// standard vocabulary, with the front end a workflow written over them is
// read with.
struct ForgeVocabulary: Sendable {
    // MARK: - Property
    // The structs forge's verbs return.
    static let runType: Name = "Forge.Run"
    static let originType: Name = "Forge.Origin"

    // The library's document, the one a workflow leans on.
    let library: Value

    // What every link holds beside the workflows: the library, the native
    // verbs under it and the standard vocabulary.
    let linkables: [Module]

    // The verbs a workflow writes, the library's procedures.
    let verbs: Set<Name>

    // The one front end forge reads a workflow with, leaning on the library.
    let frontend: YAMLFrontend

    // MARK: - Initializer
    init() throws {
        let library = try YAMLFrontend().document(from: Library.text)
        let loaded = try Loader().load(library, identity: try Identity.of(library))

        self.library = library
        self.linkables = [loaded, try Self.natives()] + Module.standard
        self.verbs = Set(loaded.procedures.keys)
        self.frontend = try YAMLFrontend(symbols: try SymbolTable(documents: [library]))
    }

    // MARK: - Public
    // The native verbs the library is written over, each with the signature
    // its action declares.
    static func natives() throws -> Module {
        try Module(
            types: [
                runType: .struct(["workflow_id": .string, "root_id": .string]),
                originType: .struct(["kind": .string, "id": .optional(.string)])
            ],
            procedures: [
                "Forge.Native.shell": Procedure(signature: ShellAction.signature, implementation: .effect(ShellAction())),
                "Forge.Native.extract": Procedure(signature: ExtractQuery.signature, implementation: .query(ExtractQuery())),
                "Forge.Native.agent": Procedure(signature: AgentAction.signature, implementation: .effect(AgentAction())),
                "Forge.Native.invoke": Procedure(signature: InvokeAction.signature, implementation: .effect(InvokeAction())),
                "Forge.Native.dispatch": Procedure(
                    signature: DispatchAction.signature,
                    implementation: .effect(DispatchAction())
                ),
                "Forge.Native.resource": Procedure(
                    signature: ResourceAction.signature,
                    implementation: .effect(ResourceAction())
                ),
                "Forge.Native.locate": Procedure(signature: LocateAction.signature, implementation: .effect(LocateAction())),
                "Forge.Native.run": Procedure(signature: RunAction.signature, implementation: .effect(RunAction())),
                "Forge.Native.origin": Procedure(signature: OriginAction.signature, implementation: .effect(OriginAction()))
            ]
        )
    }

    // MARK: - Private
}
