//
//  Reference.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// The expression language. Five shapes, all pure data — no frontend may hide an
// expression inside a string, so any FE that can spell an object can spell every
// expression:
//
//   literal            — scalars, and strings are always literal text
//   { ref: a.b[0] }    — a name to resolve in the consuming scope
//   { value: <data> }  — quotation: the payload is inert data, never evaluated;
//                        doubles as the escape for data that looks like a form
//   { format:, with: } — closed interpolation: the template sees only its
//                        declared bindings, nothing from the ambient scope
//   record / array     — elements are expressions
//
// A string is never re-parsed into anything live — the injection surface the
// old `${}` grammar carried does not exist here.
public indirect enum Reference: Sendable {
    case nullValue
    case boolValue(Bool)
    case integerValue(Int)
    case doubleValue(Double)
    case stringValue(String)
    case ref([PathSegment])
    case quoted(Value)
    case format([TemplateSegment], with: [String: Reference])
    case arrayValue([Reference])
    case recordValue([String: Reference])

    // MARK: - Property
    // The path of a plain `{ ref: }` expression — actions that require a
    // reference operand (each's material, say) name it through this.
    public var refPath: [PathSegment]? {
        guard case .ref(let path) = self else { return nil }

        return path
    }

    // The value of an expression that needs no scope — literals, quotations,
    // and compositions of them. Nil the moment any part must resolve at run
    // time. Load-time gates (an atom validating its literal operand, say) use
    // this to judge what can be judged before any run.
    public var constantValue: Value? {
        switch self {
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

        case .ref, .format:
            return nil

        case .quoted(let value):
            return value

        case .arrayValue(let array):
            let values = array.compactMap(\.constantValue)

            return values.count == array.count ? .array(values) : nil

        case .recordValue(let record):
            let values = record.compactMapValues(\.constantValue)

            return values.count == record.count ? .object(values) : nil
        }
    }

    public var referencedPaths: [[PathSegment]] {
        switch self {
        case .nullValue, .boolValue, .integerValue, .doubleValue, .stringValue:
            return []

        case .ref(let path):
            return path.expandingIndexReferences

        // Quoted data is inert — whatever ref-shaped objects it holds are data,
        // not references, so validation must not see them.
        case .quoted:
            return []

        // The template's placeholders resolve against `with`, not the ambient
        // scope — only the binding expressions reach outward.
        case .format(_, let with):
            return with.values.flatMap(\.referencedPaths)

        case .arrayValue(let array):
            return array.flatMap(\.referencedPaths)

        case .recordValue(let record):
            return record.values.flatMap(\.referencedPaths)
        }
    }

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

extension Reference: Codable {
    // The object keys that make a record an expression form. A record that
    // carries one of these as plain data must be quoted — `{ value: ... }`.
    static let formKeys: Set<String> = ["ref", "value", "format", "with"]

    public init(from decoder: Decoder) throws {
        let value = try Value(from: decoder)

        do {
            self = try Self.expression(from: value)
        } catch let error as ExpressionFormError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: error.message)
            )
        }
    }

    public static func expression(from value: Value) throws -> Reference {
        switch value {
        case .null:
            return .nullValue

        case .bool(let bool):
            return .boolValue(bool)

        case .int(let integer):
            return .integerValue(integer)

        case .double(let double):
            return .doubleValue(double)

        case .string(let string):
            return .stringValue(string)

        case .array(let array):
            return .arrayValue(try array.map(expression(from:)))

        case .object(let object):
            return try expression(fromObject: object)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .nullValue:
            try container.encodeNil()

        case .boolValue(let bool):
            try container.encode(bool)

        case .integerValue(let integer):
            try container.encode(integer)

        case .doubleValue(let double):
            try container.encode(double)

        case .stringValue(let string):
            try container.encode(string)

        case .ref(let path):
            try container.encode(["ref": path.rendered])

        case .quoted(let value):
            try container.encode(["value": value])

        case .format(let segments, let with):
            var object: [String: FormatEncoding] = [
                "format": .template(TemplateParser().render(segments))
            ]

            if !with.isEmpty { object["with"] = .bindings(with) }

            try container.encode(object)

        case .arrayValue(let array):
            try container.encode(array)

        case .recordValue(let record):
            try container.encode(record)
        }
    }

    // MARK: - Private
    private enum FormatEncoding: Encodable {
        case template(String)
        case bindings([String: Reference])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()

            switch self {
            case .template(let template):
                try container.encode(template)

            case .bindings(let bindings):
                try container.encode(bindings)
            }
        }
    }

    private static func expression(
        fromObject object: [String: Value]
    ) throws -> Reference {
        let formKeys = Set(object.keys).intersection(Self.formKeys)

        // No form key — an ordinary record of expressions.
        guard !formKeys.isEmpty else {
            return .recordValue(try object.mapValues(expression(from:)))
        }

        if object.keys.contains("ref") {
            guard object.count == 1 else {
                throw ExpressionFormError(
                    "a record with `ref` must be exactly { ref: <path> } —"
                        + " wrap it in { value: ... } if the keys are plain data"
                        + " (found keys: \(object.keys.sorted()))"
                )
            }

            guard case .string(let rendered)? = object["ref"] else {
                throw ExpressionFormError(
                    "{ ref: } takes a path string like a.b[0]"
                )
            }

            do {
                return .ref(try TemplateParser().parseRefPath(rendered))
            } catch {
                throw ExpressionFormError("{ ref: \(rendered) } — \(error)")
            }
        }

        if object.keys.contains("value") {
            guard object.count == 1, let payload = object["value"] else {
                throw ExpressionFormError(
                    "a record with `value` must be exactly { value: <data> } —"
                        + " wrap the whole record in { value: ... } if the keys are"
                        + " plain data (found keys: \(object.keys.sorted()))"
                )
            }

            return .quoted(payload)
        }

        guard object.keys.contains("format") else {
            // Only `with` remains — with is format's companion, meaningless alone.
            throw ExpressionFormError(
                "`with` only accompanies `format` — wrap the record in"
                    + " { value: ... } if the keys are plain data"
                    + " (found keys: \(object.keys.sorted()))"
            )
        }

        guard Set(object.keys).subtracting(["format", "with"]).isEmpty else {
            throw ExpressionFormError(
                "a record with `format` must be exactly { format: <template>,"
                    + " with: <bindings> } — wrap it in { value: ... } if the keys"
                    + " are plain data (found keys: \(object.keys.sorted()))"
            )
        }

        guard case .string(let template)? = object["format"] else {
            throw ExpressionFormError("{ format: } takes a template string")
        }

        let bindings: [String: Reference]

        switch object["with"] {
        case nil:
            bindings = [:]

        case .object(let withObject)?:
            bindings = try withObject.mapValues(expression(from:))

        case let other?:
            throw ExpressionFormError(
                "{ format: } `with` takes a record of bindings,"
                    + " got \(other.typeName)"
            )
        }

        let segments: [TemplateSegment]

        do {
            segments = try TemplateParser().parse(template)
        } catch {
            throw ExpressionFormError("{ format: } template — \(error)")
        }

        // The format surface is closed: every placeholder must name a declared
        // binding. An undeclared name is an author mistake caught at load, never
        // an ambient lookup at run time.
        try validateClosed(segments, over: Set(bindings.keys))

        return .format(segments, with: bindings)
    }

    private static func validateClosed(
        _ segments: [TemplateSegment],
        over declared: Set<String>
    ) throws {
        for segment in segments {
            guard case .ref(let path) = segment else { continue }

            for referenced in path.expandingIndexReferences {
                guard let head = referenced.head, declared.contains(head) else {
                    throw ExpressionFormError(
                        "{ format: } placeholder ${\(referenced.rendered)} names"
                            + " '\(referenced.head ?? referenced.rendered)', which is"
                            + " not declared in `with` — a format template sees only"
                            + " its own bindings"
                    )
                }
            }
        }
    }
}
