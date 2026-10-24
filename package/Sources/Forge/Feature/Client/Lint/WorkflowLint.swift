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
    // The files read together, as the daemon reads its catalog: each one
    // leaning on the library and on the others, loaded, and held to Forge's
    // convention, one report per path in the order given.
    package static func check(paths: [String]) -> [Report] {
        var reports: [Report?] = Array(repeating: nil, count: paths.count)
        var read: [(index: Int, data: Data, text: String)] = []

        for (index, path) in paths.enumerated() {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))

                guard let text = String(data: data, encoding: .utf8) else {
                    reports[index] = Report(path: path, readError: nil, decodeError: "the file is not UTF-8 text", issues: [])

                    continue
                }

                read.append((index, data, text))
            } catch {
                reports[index] = Report(path: path, readError: error.localizedDescription, decodeError: nil, issues: [])
            }
        }

        let leaning: (frontend: YAMLFrontend, refusals: [Int: any Error])

        do {
            leaning = try ForgeSpec.frontend(leaningOn: read.map(\.text))
        } catch {
            for file in read {
                reports[file.index] = Report(path: paths[file.index], readError: nil, decodeError: "\(error)", issues: [])
            }

            return reports.compactMap { report in report }
        }

        for (position, file) in read.enumerated() {
            let path = paths[file.index]

            if let refusal = leaning.refusals[position] {
                reports[file.index] = Report(path: path, readError: nil, decodeError: "\(refusal)", issues: [])

                continue
            }

            reports[file.index] = check(file.text, data: file.data, at: path, by: leaning.frontend)
        }

        return reports.compactMap { report in report }
    }

    // MARK: - Private
    private static func check(_ text: String, data: Data, at path: String, by frontend: YAMLFrontend) -> Report {
        let module: Warp.Module

        do {
            let document = try frontend.document(from: text)

            module = try Loader().load(document, identity: try Identity.of(document))
        } catch {
            return Report(path: path, readError: nil, decodeError: "\(error)", issues: [])
        }

        let base = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
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
