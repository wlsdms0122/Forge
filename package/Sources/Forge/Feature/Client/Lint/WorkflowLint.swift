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
    // The files built the way the daemon builds one it is asked for, with
    // what refuses each, and the authoring issues the build has no rule
    // for. One report per path in the order given.
    package func check(paths: [String]) async -> [Report] {
        var reports: [Report] = []

        for path in paths {
            let data: Data

            do {
                data = try Data(contentsOf: URL(fileURLWithPath: path))
            } catch {
                reports.append(Report(path: path, readError: error.localizedDescription, refusal: nil, issues: []))

                continue
            }

            reports.append(
                Report(
                    path: path,
                    readError: nil,
                    refusal: await refusal(of: data, at: path),
                    issues: Self.staleTemplateIssues(data: data)
                )
            )
        }

        return reports
    }

    // MARK: - Private
    private func refusal(of data: Data, at path: String) async -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return "the file is not UTF-8 text" }

        do {
            _ = try await builder.workflow(at: path, text: text)

            return nil
        } catch let refusal as WorkflowValidationError {
            return refusal.message
        } catch {
            return "\(error)"
        }
    }

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
