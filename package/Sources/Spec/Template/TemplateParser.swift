//
//  TemplateParser.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// The template dialect — `${a.b[0].c}` placeholders, `$$` escaping, `[i]`/`[${i}]`
// index references. It lives on exactly two closed surfaces: `{ format: }`
// templates and resource file bodies, both rendered against declared bindings
// only. `parseRefPath` additionally spells the path inside `{ ref: }`. Spec
// values themselves never pass through here — a string in a spec is a literal.
public struct TemplateParser: Sendable {
    // MARK: - Property
    // MARK: - Initializer
    public init() {
    }

    // MARK: - Public
    public func parse(_ text: String) throws -> [TemplateSegment] {
        var segments: [TemplateSegment] = []
        var index = text.startIndex
        var buffer = ""

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)

            if character == "$", next < text.endIndex, text[next] == "$" {
                buffer.append("$")
                index = text.index(after: next)

                continue
            }

            if character == "$", next < text.endIndex, text[next] == "{" {
                let innerStart = text.index(after: next)

                if let close = matchingBraceClose(text, from: innerStart) {
                    let inner = text[innerStart..<close]

                    if inner.trimmingCharacters(in: .whitespaces).isEmpty {
                        buffer.append(character)
                        index = next

                        continue
                    }

                    if !buffer.isEmpty {
                        segments.append(.text(buffer))
                        buffer = ""
                    }

                    segments.append(.ref(path: try parseRefPath(String(inner))))
                    index = text.index(after: close)

                    continue
                }
            }

            buffer.append(character)
            index = next
        }

        if !buffer.isEmpty { segments.append(.text(buffer)) }

        return segments
    }

    public func parseRefPath(_ inner: String) throws -> [PathSegment] {
        var segments: [PathSegment] = []
        var buffer = ""
        var depth = 0

        func flushKey() {
            let key = buffer.trimmingCharacters(in: .whitespaces)

            if !key.isEmpty { segments.append(.key(key)) }

            buffer = ""
        }

        for character in inner {
            switch character {
            case "[":
                if depth == 0 { flushKey() }

                depth += 1
                buffer.append(character)

            case "]":
                depth -= 1
                buffer.append(character)

                if depth == 0 {
                    segments.append(try indexSegment(
                        buffer.trimmingCharacters(in: .whitespaces)
                    ))
                    buffer = ""
                }

            case "." where depth == 0:
                flushKey()

            default:
                buffer.append(character)
            }
        }

        flushKey()

        guard !segments.isEmpty else {
            throw TemplateSyntaxError("empty reference path")
        }

        return segments
    }

    public func render(_ segments: [TemplateSegment]) -> String {
        segments.map { segment -> String in
            switch segment {
            case .text(let text):
                return text.replacingOccurrences(of: "$", with: "$$")

            case .ref(let path):
                return "${" + path.rendered + "}"
            }
        }
        .joined()
    }

    // MARK: - Private
    // `[3]` is a literal index; `[i]` and `[${i}]` are index references; an empty
    // `[]` is an author mistake rejected at parse, not carried into the model.
    private func indexSegment(_ bracketed: String) throws -> PathSegment {
        var inner = String(bracketed.dropFirst().dropLast())
            .trimmingCharacters(in: .whitespaces)

        if inner.hasPrefix("${"), inner.hasSuffix("}") {
            inner = String(inner.dropFirst(2).dropLast())
                .trimmingCharacters(in: .whitespaces)
        }

        if let literal = Int(inner) { return .index(literal) }

        guard !inner.isEmpty else {
            throw TemplateSyntaxError("empty index segment '[]' in reference path")
        }

        return .indexRef(try parseRefPath(inner))
    }

    private func matchingBraceClose(
        _ text: String,
        from start: String.Index
    ) -> String.Index? {
        var depth = 1
        var index = start
        var inQuotes = false

        while index < text.endIndex {
            let character = text[index]

            if character == "\"" {
                inQuotes.toggle()
            } else if !inQuotes {
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1

                    if depth == 0 { return index }
                }
            }

            index = text.index(after: index)
        }

        return nil
    }
}
