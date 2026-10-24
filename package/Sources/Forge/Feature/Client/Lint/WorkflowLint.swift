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
    // A string in a spec is a literal — an old-grammar `${...}` inside one is
    // no longer a reference and would silently ship as text. The language stays
    // inert on purpose (runtime-lowered data may legitimately carry `${`), so
    // the authored-file gate is where the migration trap gets loud. Exempt:
    // `format` templates (the dialect's home), metadata prose, and `{ value: }`
    // quotations (the sanctioned escape for literal `${` text).
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
                    "\(location): string contains '${' — strings are literals now;"
                        + " use { format:, with: } to interpolate, or wrap in"
                        + " { value: } if the text is meant verbatim"
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

            // A single-key { value: } map is the quotation form — its payload
            // is data by declaration, not a stale template.
            if entries.count == 1, entries.first?.0 == "value" { return }

            for (key, element) in entries.sorted(by: { one, other in one.0 < other.0 }) {
                guard !Self.proseKeys.contains(key) else { continue }

                walk(element, at: "\(location).\(key)", into: &issues)
            }

        case .null, .bool, .int, .double, .bytes, .struct, .existential:
            break
        }
    }
}
