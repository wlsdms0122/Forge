//
//  WorkflowReader.swift
//  Forge
//
//  Created by JSilver on 11/1/26.
//

import Foundation
import Warp
import WarpSyntax
import WarpYAML

// The workflows a daemon runs, read when one is named. A workflow is the
// file at a path, built over the vocabulary when it is asked
// for and built again only where the file changed since; an inline spec is
// one procedure handed in place of a path.
actor WorkflowReader {
    private struct Entry {
        // MARK: - Property
        let workflow: Workflow
        let mtime: Date
        let image: Image

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    // What the workflows are written over, which every run of one links.
    let vocabulary: ForgeVocabulary

    private let workingDirectory: WorkingDirectory
    private let builder: WorkflowBuilder
    private var built: [String: Entry] = [:]

    // MARK: - Initializer
    init(workingDirectory: WorkingDirectory, builder: WorkflowBuilder) {
        self.workingDirectory = workingDirectory
        self.vocabulary = builder.vocabulary
        self.builder = builder
    }

    // MARK: - Public
    // The workflow at this path. The path is its identity, which a policy
    // matches.
    func workflow(at path: String) async throws -> Workflow {
        guard path != Workflow.inlineSigil else {
            throw ResourceError("'\(path)' names an inline spec, not a file")
        }

        guard let url = try await workingDirectory.file(at: path) else {
            built[path] = nil

            throw WorkflowNotFound("workflow not found: \(path)")
        }

        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? .distantPast

        if let entry = built[path], entry.mtime == mtime { return entry.workflow }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let read = try await builder.workflow(at: path, text: text)

            built[path] = Entry(workflow: read.workflow, mtime: mtime, image: read.image)

            return read.workflow
        } catch {
            built[path] = nil

            throw WorkflowValidationError("workflow '\(path)' is broken: \(Self.reason(error))")
        }
    }

    // An inline spec: one procedure written in the YAML notation, read the
    // way a file is, leaning on the library, and declared as the entry a run
    // starts from.
    func inline(_ spec: [String: JSONValue]) async throws -> Workflow {
        var procedure = spec

        procedure["access"] = .string("public")

        let written = JSONValue.object(["procedures": .object([Workflow.entry: .object(procedure)])])
        let spent: Data

        do {
            spent = try vocabulary.frontend.document(from: try JSONEncoder().encode(written)).document
        } catch let refusal as AuthoringError {
            throw WorkflowValidationError(refusal.message)
        }

        let document = try BinaryEncoding().value(from: spent)

        return try Workflow(
            path: Workflow.inlineSigil,
            module: try Loader().load(document),
            documentation: nil
        )
    }

    // The image a run of this workflow runs: for a file, the
    // one built when it was read; for an inline spec, its module built alone.
    func image(of workflow: Workflow) async throws -> Image {
        if let entry = built[workflow.path], entry.workflow.module.identity == workflow.module.identity {
            return entry.image
        }

        return try await builder.image(of: workflow.module)
    }

    // MARK: - Private
    private static func reason(_ error: any Error) -> String {
        (error as? WorkflowValidationError)?.message ?? "\(error)"
    }
}
