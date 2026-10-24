//
//  WorkflowLint.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Warp
import WarpSyntax
import WarpYAML

package enum WorkflowLint {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    package static func check(path: String) -> Report {
        let url = URL(fileURLWithPath: path)
        let data: Data

        do {
            data = try Data(contentsOf: url)
        } catch {
            return Report(
                path: path,
                readError: error.localizedDescription,
                decodeError: nil,
                issues: []
            )
        }

        let module: Warp.Module

        do {
            let document = try ForgeSpec.frontend().document(from: data)

            module = try Loader().load(document, identity: try Identity.of(document))
        } catch {
            return Report(
                path: path,
                readError: nil,
                decodeError: "\(error)",
                issues: []
            )
        }

        let base = url.deletingPathExtension().lastPathComponent
        var issues: [String] = []

        if module.procedures.keys.map(\.spelling) != [base] {
            issues.append(
                "a workflow file declares exactly one procedure named after the file"
                    + " — expected 'procedures: { \(base): ... }'"
            )
        }

        issues += staleTemplateIssues(data: data)

        return Report(path: path, readError: nil, decodeError: nil, issues: issues)
    }

    // MARK: - Private
    // A string in a workflow is a literal, so a `${...}` inside one ships as
    // text. The language takes it as text on purpose (data may carry `${`),
    // and the authored file is where an interpolation written as a plain
    // string gets loud. Exempt: a `format` template, whose `$$` writes `$`,
    // and the prose the front end takes beside the document (`description`,
    // `hint`).
    private static func staleTemplateIssues(data: Data) -> [String] {
        guard let tree = try? YAMLParser().parse(data) else {
            return []
        }

        var issues: [String] = []

        walk(tree, at: "spec", into: &issues)

        return issues
    }

    private static let proseKeys: Set<String> = ["format", "description", "hint"]

    private static func walk(
        _ value: Warp.Value,
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

        // What a document parses to is never code, so there is nothing here to
        // walk into.
        case .procedure:
            return

        case let .array(array):
            for (index, element) in array.enumerated() {
                walk(element, at: "\(location)[\(index)]", into: &issues)
            }

        case let .dictionary(object):
            let entries = zip(object.keys, object.values).map { key, element in (ValueBridge.text(key), element) }

            for (key, element) in entries.sorted(by: { one, other in one.0 < other.0 }) {
                guard !Self.proseKeys.contains(key) else { continue }

                walk(element, at: "\(location).\(key)", into: &issues)
            }

        case .null, .bool, .int, .double, .bytes, .struct, .existential:
            break
        }
    }
}
