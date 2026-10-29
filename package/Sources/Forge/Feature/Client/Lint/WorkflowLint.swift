//
//  WorkflowLint.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

package struct WorkflowLint: Sendable {
    // MARK: - Property
    // How the files are built, the daemon's way.
    let builder: WorkflowBuilder

    // MARK: - Initializer
    // A lint over the vocabulary the binary carries.
    package init() throws {
        self.init(builder: WorkflowBuilder(vocabulary: try ForgeVocabulary()))
    }

    init(builder: WorkflowBuilder) {
        self.builder = builder
    }

    // MARK: - Public
    // The files admitted as the daemon admits its catalog's at a reload,
    // read through the catalog itself, with what it records for each, and
    // the authoring issues the catalog has no rule for. One report per path
    // in the order given.
    package func check(paths: [String]) async -> [Report] {
        var read: [(path: String, data: Data)] = []
        var unread: [String: String] = [:]

        for path in paths {
            do {
                read.append((path, try Data(contentsOf: URL(fileURLWithPath: path))))
            } catch {
                unread[path] = error.localizedDescription
            }
        }

        let snapshot = await WorkflowCatalog(directory: nil, builder: builder).reload(of: read.map(\.path))
        let refusals = Dictionary(
            snapshot.failures.map { failure in (failure.path, failure.reason) },
            uniquingKeysWith: { first, _ in first }
        )
        let issues = Dictionary(
            read.map { file in (file.path, Self.staleTemplateIssues(data: file.data)) },
            uniquingKeysWith: { first, _ in first }
        )

        return paths.map { path in
            Report(path: path, readError: unread[path], refusal: refusals[path], issues: issues[path] ?? [])
        }
    }

    // MARK: - Private
    // A string in a workflow is a literal, so a `${...}` inside one ships as
    // text. The language takes it as text on purpose (data may carry `${`),
    // and the authored file is where an interpolation written as a plain
    // string gets loud. Exempt: a `format` template, whose `$$` writes `$`,
    // and the prose the front end takes beside the document (`description`,
    // `hint`).
    private static func staleTemplateIssues(data: Data) -> [String] {
        guard let tree = try? YAMLSpec.decode(JSONValue.self, from: data) else {
            return []
        }

        var issues: [String] = []

        walk(tree, at: "spec", into: &issues)

        return issues
    }

    private static let proseKeys: Set<String> = ["format", "description", "hint"]

    private static func walk(
        _ value: JSONValue,
        at location: String,
        into issues: inout [String]
    ) {
        switch value {
        case let .string(string):
            if string.contains("${") {
                issues.append(
                    "\(location): string contains '${', and a string is a literal;"
                        + " use { format:, with: } to interpolate, where '$$' writes '$'"
                )
            }

        case let .array(array):
            for (index, element) in array.enumerated() {
                walk(element, at: "\(location)[\(index)]", into: &issues)
            }

        case let .object(object):
            for (key, element) in object.sorted(by: { one, other in one.key < other.key }) {
                guard !Self.proseKeys.contains(key) else { continue }

                walk(element, at: "\(location).\(key)", into: &issues)
            }

        case .null, .bool, .int, .double:
            break
        }
    }
}
