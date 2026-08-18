//
//  WorkflowContract.swift
//  Forge
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import Warp
import WarpIR

// The JSON shape `workflow.describe` answers with. It is written here rather
// than falling out of the language's own conformances: an RPC contract forge is
// responsible for should not be defined by how the language happens to spell
// its IR.
struct WorkflowContract {
    // MARK: - Property
    // MARK: - Initializer
    init() {
    }

    // MARK: - Public
    func inputs(of signature: Signature) throws -> [String: Any] {
        // The names the daemon supplies are declared on every procedure so the
        // language can see them, but they are not part of the contract a caller
        // fills in — describing them would invite callers to pass them.
        try signature.parameters
            .filter { name, _ in !ForgeSpec.ambient.contains(name) }
            .mapValues { parameter in try self.parameter(parameter) }
    }

    // A procedure answers one expression. This notation writes several named
    // outputs, which the reader lowers to one record — so describing them is
    // reading that record's fields back, and anything else answers nothing to
    // describe.
    func outputs(of result: Warp.Expression?) throws -> [String: Any] {
        guard case .record(let fields)? = result else { return [:] }

        return try fields.mapValues { expression in try self.expression(expression) }
    }

    // MARK: - Private
    private func parameter(_ parameter: Parameter) throws -> [String: Any] {
        var described: [String: Any] = ["type": parameter.type.rendered]

        if let oneOf = parameter.oneOf { described["oneOf"] = oneOf }
        if let hint = parameter.hint { described["hint"] = hint }

        // A declared default is what makes an input optional, so a default of
        // null must still put the key on the wire.
        if let fallback = parameter.default {
            described["default"] = try value(fallback)
        }

        return described
    }

    private func expression(_ expression: Warp.Expression) throws -> Any {
        switch expression {
        // A composite literal has to go back out quoted: bare, the reader would
        // read its fields as expressions again. Scalars have no form to be
        // mistaken for.
        case .literal(let literal):
            switch literal {
            case .array, .object:
                return ["value": try value(literal)]

            default:
                return try value(literal)
            }

        case .reference(let path):
            return ["ref": path.rendered]

        case .format(let segments, let with):
            var described: [String: Any] = [
                "format": TemplateParser().render(segments)
            ]

            if !with.isEmpty {
                described["with"] = try with.mapValues { binding in
                    try self.expression(binding)
                }
            }

            return described

        case .array(let array):
            return try array.map { element in try self.expression(element) }

        case .record(let record):
            return try record.mapValues { field in try self.expression(field) }

        // A declared output is data, not a construct: no notation writes a
        // condition or a body in that slot, so these are unreachable rather
        // than unhandled.
        default:
            throw ProtocolError(
                "workflow.describe: an output must be data, not a construct"
            )
        }
    }

    private func value(_ value: Value) throws -> Any {
        let data = try JSONEncoder().encode(value)

        return try JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        )
    }
}
