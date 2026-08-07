//
//  Scope.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

public struct Scope: Sendable {
    // MARK: - Property
    public static let inputsHead = "inputs"

    public private(set) var inputs: [String: Value]
    public private(set) var contexts: [String: [String: Value]]
    public var bindings: [String: Value]

    public var reservedHeads: Set<String> {
        Set(contexts.keys).union([Self.inputsHead])
    }

    private let library: SpecLibrary
    private let bindingsOnly: Bool

    // MARK: - Initializer
    public init(
        inputs: [String: Value] = [:],
        contexts: [String: [String: Value]] = [:],
        bindings: [String: Value] = [:],
        library: SpecLibrary = .standard
    ) {
        self.inputs = inputs
        self.contexts = contexts
        self.bindings = bindings
        self.library = library
        self.bindingsOnly = false
    }

    private init(closedOver bindings: [String: Value], library: SpecLibrary) {
        self.inputs = [:]
        self.contexts = [:]
        self.bindings = bindings
        self.library = library
        self.bindingsOnly = true
    }

    // A closed scope serves nothing but the given bindings — no reserved heads
    // exist, so a binding named `inputs` is just a binding. This is the scope
    // the closed render surfaces (format expressions, resource bodies) use;
    // without it the general lookup's reserved-head precedence would silently
    // shadow a declared binding with an empty object.
    public static func closed(
        bindings: [String: Value],
        library: SpecLibrary = .standard
    ) -> Scope {
        Scope(closedOver: bindings, library: library)
    }

    // MARK: - Public
    public func lookup(_ path: [PathSegment]) -> Lookup {
        let resolvedPath: [PathSegment]

        switch resolveIndexReferences(path) {
        case .resolved(let resolved):
            resolvedPath = resolved

        case .failed(let lookup):
            return lookup
        }

        guard case .key(let head)? = resolvedPath.first else { return .absent }

        let rest = Array(resolvedPath.dropFirst())

        if bindingsOnly {
            guard let bound = bindings[head] else { return .absent }

            return drill(into: bound, rest, at: [.key(head)])
        }

        if head == Self.inputsHead {
            return drill(into: .object(inputs), rest, at: [.key(head)])
        }

        if let context = contexts[head] {
            return drill(into: .object(context), rest, at: [.key(head)])
        }

        guard let bound = bindings[head] else { return .absent }

        return drill(into: bound, rest, at: [.key(head)])
    }

    public func binding(_ id: String, to value: Value) -> Scope {
        var scope = self

        scope.bindings[id] = value

        return scope
    }

    // MARK: - Private
    private enum IndexResolution {
        case resolved([PathSegment])
        case failed(Lookup)
    }

    private func resolveIndexReferences(_ path: [PathSegment]) -> IndexResolution {
        var out: [PathSegment] = []

        for segment in path {
            guard case .indexRef(let indexPath) = segment else {
                out.append(segment)

                continue
            }

            let name = indexPath.rendered

            switch lookup(indexPath) {
            case .found(.int(let index)):
                out.append(.index(index))

            case .found(.double(let double)):
                guard let index = Int(exactly: double) else {
                    return .failed(.unfit(
                        reason: "index reference \(name) is not a whole number"
                    ))
                }

                out.append(.index(index))

            case .found(let value):
                return .failed(.unfit(
                    reason: "index reference \(name) is \(value.typeName), expected int"
                ))

            case .absent:
                return .failed(.absent)

            case .unfit(let reason):
                return .failed(.unfit(reason: reason))
            }
        }

        return .resolved(out)
    }

    private func drill(
        into value: Value,
        _ path: [PathSegment],
        at walked: [PathSegment]
    ) -> Lookup {
        var current = value
        var walked = walked

        for segment in path {
            walked.append(segment)

            switch (segment, current) {
            // Anything derived from nothing is still nothing — drilling into null
            // (a skipped step, an omitted optional) is absence, not shape misuse.
            case (_, .null):
                return .absent

            case (.index(let index), .array(let array)):
                guard index >= 0, index < array.count else { return .absent }

                current = array[index]

            case (.index, _):
                return .unfit(
                    reason: "\(walked.rendered) indexes into"
                        + " \(current.typeName), expected array"
                )

            case (.key(let key), .object(let object)):
                guard let next = object[key] else {
                    guard let derived = derive(key, from: current) else { return .absent }

                    current = derived

                    continue
                }

                current = next

            case (.key(let key), _):
                guard let derived = derive(key, from: current) else {
                    return .unfit(
                        reason: "\(walked.rendered) drills a field into"
                            + " \(current.typeName)"
                    )
                }

                current = derived

            case (.indexRef, _):
                preconditionFailure("index references are resolved before drilling")
            }
        }

        return .found(current)
    }

    // Derivations are library vocabulary, not language structure — the scope only
    // consults them; what words exist is the host's SpecLibrary configuration.
    private func derive(_ key: String, from value: Value) -> Value? {
        library.derivations[key]?.derive(value)
    }
}
