//
//  WorkflowBuilder.swift
//  Forge
//
//  Created by JSilver on 10/24/26.
//

import Foundation
import Warp
import WarpSyntax
import WarpYAML

// How a workflow is built over a vocabulary. The vocabulary is compiled
// once, laid down as a compile against it reads it, with the native code it
// brings; a workflow is compiled against it and linked beside it.
struct WorkflowBuilder: Sendable {
    // MARK: - Property
    let vocabulary: ForgeVocabulary

    private let built: Task<(compiled: [Compiled], laid: Laid, supplying: Supplying), any Error>

    // MARK: - Initializer
    init(vocabulary: ForgeVocabulary) {
        self.vocabulary = vocabulary
        self.built = Task {
            let modules = vocabulary.linkables
            let supplying = try Supplying(modules)
            let compiled = try await Builder().compile(modules, against: [], supplying: supplying)

            return (compiled: compiled, laid: try Builder().lay(compiled, supplying: supplying), supplying: supplying)
        }
    }

    // MARK: - Public
    // A workflow file's text read leaning on the library, loaded the way a
    // runtime receives a document, held to Forge's convention and built, or
    // refused with what refused it.
    func workflow(at path: String, text: String) async throws -> (workflow: Workflow, image: Image) {
        var origin: DocumentOrigin?

        do {
            let spent = try vocabulary.frontend.document(from: text)
            let document = try BinaryEncoding().value(from: spent.document)
            let loading = DocumentOrigin(identity: try Identity.of(document), origin: spent.origin)

            origin = loading

            let module = try Loader().load(document)

            if let breach = Self.convention(module) { throw WorkflowValidationError(breach) }

            let workflow = try Workflow(
                path: path,
                module: module,
                documentation: try vocabulary.frontend.documentation(from: text)
            )

            do {
                return (workflow, try await image(of: module))
            } catch {
                throw WorkflowValidationError("build: \(loading.described(error))")
            }
        } catch let refusal as WorkflowValidationError {
            throw refusal
        } catch {
            throw WorkflowValidationError(origin.map { origin in origin.described(error) } ?? "\(error)")
        }
    }

    // The image a workflow runs: its module compiled against the vocabulary
    // as it was laid down once, and linked beside it.
    func image(of module: Module) async throws -> Image {
        let vocabulary = try await built.value
        let compiled = try await Builder().compile([module], against: vocabulary.laid)

        return try Builder().link(vocabulary.compiled + compiled, supplying: vocabulary.supplying)
    }

    // MARK: - Private
    // Forge's convention on top of the language: a workflow file declares
    // its entry, a public procedure named `main`, which a run starts from.
    // The breach, where the file makes one.
    private static func convention(_ module: Warp.Module) -> String? {
        guard
            let entry = try? Warp.Name(Workflow.entry),
            let procedure = module.procedures[entry]
        else {
            return "a workflow file declares the procedure '\(Workflow.entry)' a run starts from;"
                + " found \(module.procedures.keys.map { key in "'\(key.spelling)'" }.sorted().joined(separator: ", "))"
        }

        guard procedure.access == .public else {
            return "'\(Workflow.entry)' is the procedure a run starts from, so it is 'access: public'"
        }

        return nil
    }
}
