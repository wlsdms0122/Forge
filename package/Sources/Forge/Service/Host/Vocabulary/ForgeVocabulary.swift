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

enum ForgeVocabulary {
    // MARK: - Property
    // The structs forge's verbs return.
    static let runType: Name = "Forge.Run"
    static let originType: Name = "Forge.Origin"

    // Forge's grammar: the library document the binary carries, written in
    // the YAML notation over the native verbs and spent once. A workflow
    // leans on it and every link holds it.
    private static let shipped = Result {
        try YAMLFrontend().document(from: Library.text)
    }

    // The library loaded the way a runtime receives it.
    private static let loaded = Result {
        let document = try shipped.get()

        return try Loader().load(document, identity: try Identity.of(document))
    }

    // The front end leaning on the library.
    private static let leaning = Result {
        try YAMLFrontend(symbols: try SymbolTable(documents: [try shipped.get()]))
    }

    // The library, the natives and std compiled once a process, laid down
    // as a compile against them reads them, and the native code they bring:
    // they are fixed for its life, so a build of workflows compiles the
    // workflows and links them beside these.
    private static let built = Task {
        let modules = try linkables()
        let supplying = try Supplying(modules)
        let compiled = try await Builder().compile(modules, against: [], supplying: supplying)

        return (compiled: compiled, laid: try Builder().lay(compiled, supplying: supplying), supplying: supplying)
    }

    // MARK: - Initializer
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

    // The library's document, the one a workflow leans on.
    static func library() throws -> Value {
        try shipped.get()
    }

    // The verbs a workflow writes, the library's procedures.
    static func verbs() throws -> Set<Name> {
        Set(try loaded.get().procedures.keys)
    }

    // What every link holds beside the workflows: the library, the native
    // verbs under it and the standard vocabulary.
    static func linkables() throws -> [Module] {
        [try loaded.get(), try natives()] + Module.standard
    }

    // Workflows compiled against the vocabulary and the workflows already
    // compiled beside it, in the order they are handed: against the
    // vocabulary as it was laid down once, where nothing stands beside it.
    static func compiled(_ modules: [Module], beside standing: [Compiled] = []) async throws -> [Compiled] {
        let vocabulary = try await built.value

        guard !standing.isEmpty else {
            return try await Builder().compile(modules, against: vocabulary.laid)
        }

        return try await Builder().compile(modules, against: vocabulary.compiled + standing, supplying: vocabulary.supplying)
    }

    // The image of compiled workflows linked beside the vocabulary.
    static func linked(_ compiled: [Compiled]) async throws -> Image {
        let vocabulary = try await built.value

        return try Builder().link(vocabulary.compiled + compiled, supplying: vocabulary.supplying)
    }

    // The one front end forge reads a workflow with, leaning on the library.
    static func frontend() throws -> YAMLFrontend {
        try leaning.get()
    }

    // The front end leaning on the library and on these texts, which lean on
    // each other. A text that does not parse leans on nothing, and its
    // refusal, as it reads alone, is handed back under its position.
    static func frontend(leaningOn texts: [String]) throws -> (frontend: YAMLFrontend, refusals: [Int: any Error]) {
        let frontend = try frontend()
        var standing = Array(texts.indices)
        var refusals: [Int: any Error] = [:]

        while true {
            do {
                return (try frontend.leaning(on: standing.map { index in texts[index] }), refusals)
            } catch let refusal as AuthoringError {
                guard let position = refusal.text else { throw refusal }

                let index = standing.remove(at: position)

                do {
                    _ = try frontend.document(from: texts[index])
                    refusals[index] = refusal
                } catch {
                    refusals[index] = error
                }
            }
        }
    }

    // MARK: - Private
}
