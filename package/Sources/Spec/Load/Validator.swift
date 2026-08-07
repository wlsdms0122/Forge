//
//  Validator.swift
//  Spec
//
//  Created by JSilver on 8/8/26.
//

import Foundation

public struct Validator: Sendable {
    // MARK: - Property
    public let contextHeads: Set<String>

    // MARK: - Initializer
    public init(contextHeads: Set<String> = []) {
        self.contextHeads = contextHeads
    }

    // MARK: - Public
    // The runtime lowering door must pass the same gate the load path does —
    // steps that arrived as data get validated against the heads visible where
    // they will run.
    public func validate(steps: [Step], visible: Set<String>) throws {
        try validate(steps, visible: visible, label: "lowered")
    }

    public func validate(_ spec: Program) throws {
        let known = Set([Scope.inputsHead]).union(contextHeads)
        let visible = try validate(spec.steps, visible: known, label: "steps")

        for (name, reference) in (spec.outputs ?? [:]).sorted(by: { $0.key < $1.key }) {
            try validate(
                paths: reference.referencedPaths,
                visible: visible,
                at: "outputs.\(name)"
            )
        }
    }

    // MARK: - Private
    @discardableResult
    private func validate(
        _ steps: [Step],
        visible startVisible: Set<String>,
        label: String
    ) throws -> Set<String> {
        var visible = startVisible
        var declared: Set<String> = []

        for step in steps {
            guard !step.id.isEmpty else {
                throw ValidationError("\(label): step with empty id")
            }

            guard step.id != Scope.inputsHead, !contextHeads.contains(step.id) else {
                throw ValidationError(
                    "\(label): step id '\(step.id)' collides with a reserved scope head"
                )
            }

            // Sub scopes restart declaration tracking, so an inner step may reuse an
            // outer id — the retry-loop idiom rebinds the outer id on purpose. Only
            // same-level duplicates are ambiguous.
            guard !declared.contains(step.id) else {
                throw ValidationError("\(label): duplicate step id '\(step.id)'")
            }

            declared.insert(step.id)

            let innerVisible = visible.union([step.id])

            try validate(
                paths: step.when?.referencedPaths ?? [],
                visible: visible,
                at: "\(label).\(step.id).when"
            )
            // The step's own id is visible only where the action declares it binds
            // one — loop's round state, not a group's body.
            try validate(
                paths: step.action.referencedPaths,
                visible: step.action.referencesOwnID ? innerVisible : visible,
                at: "\(label).\(step.id)"
            )

            for scopeDeclaration in step.action.scopeDeclarations {
                let subVisible = try validate(
                    scopeDeclaration.steps,
                    visible: scopeDeclaration.bindsOwnID ? innerVisible : visible,
                    label: "\(label).\(step.id).\(scopeDeclaration.label)"
                )

                try validate(
                    paths: scopeDeclaration.trailingPaths,
                    visible: subVisible,
                    at: "\(label).\(step.id).\(scopeDeclaration.label).output"
                )
            }

            if let rescue = step.rescue {
                // An empty rescue would swallow a failure into `.null` without a
                // trace — if the alternate path produces nothing, the author's
                // honest form is no rescue at all.
                guard !rescue.isEmpty else {
                    throw ValidationError("\(label).\(step.id).rescue: must not be empty")
                }

                // While a rescue runs, the failed step's id names the failure
                // payload — so the rescue's steps may reference it.
                try validate(
                    rescue,
                    visible: innerVisible,
                    label: "\(label).\(step.id).rescue"
                )
            }

            visible.insert(step.id)
        }

        return visible
    }

    private func validate(
        paths: [[PathSegment]],
        visible: Set<String>,
        at location: String
    ) throws {
        for path in paths {
            guard let head = path.head else {
                throw ValidationError(
                    "\(location): reference { ref: \(path.rendered) } does not"
                        + " start with a name"
                )
            }

            guard visible.contains(head) else {
                throw ValidationError(
                    "\(location): reference { ref: \(path.rendered) } names"
                        + " '\(head)', which is not visible here — declare it earlier"
                        + " or check the spelling"
                )
            }
        }
    }
}
