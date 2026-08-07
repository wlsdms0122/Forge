//
//  Resolver.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

public struct Resolver: Sendable {
    // MARK: - Property
    public let scope: Scope
    public let library: SpecLibrary

    // MARK: - Initializer
    public init(scope: Scope, library: SpecLibrary = .standard) {
        self.scope = scope
        self.library = library
    }

    // MARK: - Public
    public func resolve(_ reference: Reference) throws -> Value {
        switch reference {
        case .nullValue:
            return .null

        case .boolValue(let bool):
            return .bool(bool)

        case .integerValue(let integer):
            return .int(integer)

        case .doubleValue(let double):
            return .double(double)

        case .stringValue(let string):
            return .string(string)

        case .ref(let path):
            return try found(at: path)

        // Quotation — the payload passes through verbatim, never evaluated.
        case .quoted(let value):
            return value

        // The bindings are expressions evaluated here; the template then renders
        // against them alone — a closed surface over the declared names.
        case .format(let segments, let with):
            let bindings = try with.mapValues(resolve)

            return .string(try Self.render(
                segments,
                scope: .closed(bindings: bindings, library: library)
            ))

        case .arrayValue(let array):
            return .array(try array.map(resolve))

        case .recordValue(let record):
            return .object(try record.mapValues(resolve))
        }
    }

    // The one renderer for the template dialect's two closed surfaces — format
    // expressions and resource bodies. The scope holds nothing but the declared
    // bindings, so a placeholder can only ever see what the author handed it —
    // pass a `Scope.closed`, or reserved heads shadow same-named bindings.
    public static func render(
        _ segments: [TemplateSegment],
        scope: Scope
    ) throws -> String {
        let resolver = Resolver(scope: scope)
        var out = ""

        for segment in segments {
            switch segment {
            case .text(let text):
                out += text

            case .ref(let path):
                let value: Value

                switch scope.lookup(path) {
                case .found(let found):
                    value = found

                case .absent:
                    throw ReferenceNotFound(path: path)

                case .unfit(let reason):
                    throw ReferenceUnfit(path: path, reason: reason)
                }

                // The author interpolated this name assuming a value exists —
                // completing the text with "" for null would be the engine
                // typing what the author never wrote.
                guard value != .null else {
                    throw ReferenceUnfit(path: path, reason: "null inside a template")
                }

                out += resolver.stringify(value)
            }
        }

        return out
    }

    public func string(_ reference: Reference) throws -> String {
        stringify(try resolve(reference))
    }

    public func stringify(_ value: Value) -> String {
        switch value {
        case .null:
            return ""

        case .bool(let bool):
            return bool ? "true" : "false"

        case .int(let integer):
            return String(integer)

        case .double(let double):
            return String(double)

        case .string(let string):
            return string

        case .array, .object:
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

                let data = try encoder.encode(value)

                return String(data: data, encoding: .utf8) ?? "<unencodable>"
            } catch {
                return "<unencodable>"
            }
        }
    }

    public func evaluate(_ condition: Condition) throws -> Bool {
        switch condition {
        case .allOf(let conditions):
            for condition in conditions where try !evaluate(condition) { return false }

            return true

        case .anyOf(let conditions):
            for condition in conditions where try evaluate(condition) { return true }

            return false

        case .not(let condition):
            return try !evaluate(condition)

        case .predicate(let subject, let `operator`, let operand):
            // A plain reference subject keeps the absence policy — is answers
            // false, is_not true, present false; every other subject shape is a
            // full expression and resolves strictly.
            let resolved: Value?

            if let path = subject.refPath {
                switch scope.lookup(path) {
                case .found(let found):
                    resolved = found

                case .absent:
                    resolved = nil

                case .unfit(let reason):
                    throw ReferenceUnfit(path: path, reason: reason)
                }
            } else {
                resolved = try resolve(subject)
            }

            switch `operator` {
            case .is:
                guard let operand, let resolved else { return false }

                return resolved.matches(try resolve(operand))

            case .isNot:
                guard let operand else { return false }
                guard let resolved else { return true }

                return !resolved.matches(try resolve(operand))

            case .oneOf:
                guard let operand, let resolved else { return false }

                let candidates = try resolve(operand)

                guard case .array(let values) = candidates else {
                    throw ExecutionError(
                        "one_of needs an array operand, got \(candidates.typeName)"
                    )
                }

                return values.contains { candidate in candidate.matches(resolved) }

            case .present:
                if let resolved, resolved != .null { return true }

                return false

            case .atom(let name):
                guard let atom = library.atoms[name] else {
                    throw ExecutionError("no predicate atom registered for '\(name)'")
                }

                guard let operand else { return false }

                return try atom.evaluate(
                    resolved,
                    try resolve(operand),
                    subject.refPath ?? []
                )
            }
        }
    }

    // MARK: - Private
    private func found(at path: [PathSegment]) throws -> Value {
        switch scope.lookup(path) {
        case .found(let value):
            return value

        case .absent:
            throw ReferenceNotFound(path: path)

        case .unfit(let reason):
            throw ReferenceUnfit(path: path, reason: reason)
        }
    }

}
