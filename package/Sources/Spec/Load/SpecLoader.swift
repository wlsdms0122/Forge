//
//  SpecLoader.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Yams

public struct SpecLoader: Sendable {
    // MARK: - Property
    public let registry: ActionRegistry
    public let library: SpecLibrary
    public let contextHeads: Set<String>

    // MARK: - Initializer
    public init(
        registry: ActionRegistry = .standard,
        library: SpecLibrary = .standard,
        contextHeads: Set<String> = []
    ) {
        self.registry = registry
        self.library = library
        self.contextHeads = contextHeads
    }

    // MARK: - Public
    // The loader is the one door a host configures — deriving the executor from
    // it keeps the vocabulary that validated a spec identical to the vocabulary
    // that runs it.
    public func makeExecutor(
        store: (any SpecStore)? = nil,
        observer: (any ExecutionObserver)? = nil,
        environment: (any Sendable)? = nil
    ) -> Executor {
        Executor(
            store: store,
            observer: observer,
            library: library,
            environment: environment
        )
    }

    public func load(_ data: Data) throws -> Program {
        let spec = try decode(Program.self, from: data)

        try Validator(contextHeads: contextHeads).validate(spec)

        return spec
    }

    public func load(_ text: String) throws -> Program {
        try load(Data(text.utf8))
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decode(type, from: try value(fromYAML: data))
    }

    // The official runtime lowering door — data that arrived as a Value (a step
    // array through a signature, say) becomes IR through the same decoder and
    // registry the load path uses. No text is re-parsed; the frontend is simply
    // invoked at run time.
    public func decode<T: Decodable>(_ type: T.Type, from value: Value) throws -> T {
        try T(from: ValueDecoder(
            value: value,
            codingPath: [],
            userInfo: [
                .actionRegistry: registry,
                .specLibrary: library,
                .specLoader: self
            ]
        ))
    }

    // Lowering a whole program passes the same gate `load` does — decode alone
    // is not a door into the IR.
    public func lower(_ value: Value) throws -> Program {
        let program = try decode(Program.self, from: value)

        try Validator(contextHeads: contextHeads).validate(program)

        return program
    }

    // MARK: - Private
    private func value(fromYAML data: Data) throws -> Value {
        guard let text = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "spec file is not valid UTF-8")
            )
        }

        let root: Node?

        do {
            root = try Yams.compose(yaml: text)
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription: "The given data was not valid YAML.",
                    underlyingError: error
                )
            )
        }

        guard let root else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "empty YAML document")
            )
        }

        return try value(fromNode: root)
    }

    private func value(fromNode node: Node) throws -> Value {
        switch node {
        case .scalar(let scalar):
            return try value(fromScalar: scalar)

        case .sequence(let sequence):
            return .array(try sequence.map(value(fromNode:)))

        case .mapping(let mapping):
            var object: [String: Value] = [:]

            for (key, entry) in mapping {
                guard case .scalar(let scalarKey) = key else {
                    throw DecodingError.dataCorrupted(
                        .init(
                            codingPath: [],
                            debugDescription: "non-scalar mapping key is not supported in specs"
                        )
                    )
                }

                object[scalarKey.string] = try value(fromNode: entry)
            }

            return .object(object)

        // compose resolves aliases into their anchored values before this walk —
        // aliases work in specs. This branch is defensive against a future Yams
        // surfacing one unresolved.
        case .alias:
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription: "unresolved YAML alias — compose should have"
                        + " resolved it"
                )
            )
        }
    }

    private func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    // Only plain scalars are retyped, and only by JSON literal rules — `no`, `on`,
    // `09:20`, `007` stay strings instead of taking YAML 1.1 reinterpretation, and
    // quoted/block scalars are always strings.
    private func value(fromScalar scalar: Node.Scalar) throws -> Value {
        guard scalar.style == .plain || scalar.style == .any else {
            return .string(scalar.string)
        }

        let text = scalar.string

        switch text {
        case "", "~", "null":
            return .null

        case "true":
            return .bool(true)

        case "false":
            return .bool(false)

        default:
            if matches(text, #"^-?(0|[1-9][0-9]*)$"#), let integer = Int(text) {
                return .int(integer)
            }

            if
                matches(text, #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#),
                let double = Double(text)
            {
                guard double.isFinite else {
                    throw DecodingError.dataCorrupted(
                        .init(
                            codingPath: [],
                            debugDescription: "numeric literal '\(text)' overflows the JSON"
                                + " number range — quote it if you meant a string"
                        )
                    )
                }

                return .double(double)
            }

            return .string(text)
        }
    }
}

public extension CodingUserInfoKey {
    static let actionRegistry = CodingUserInfoKey(rawValue: "spec.actionRegistry")!
    static let specLibrary = CodingUserInfoKey(rawValue: "spec.library")!
    static let specLoader = CodingUserInfoKey(rawValue: "spec.loader")!
}
