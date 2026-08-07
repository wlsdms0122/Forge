//
//  WorkflowEvent.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct WorkflowEvent: Sendable {
    // MARK: - Property
    let kind: WorkflowEventKind
    let workflowID: String
    let workflowName: String
    let stepID: String?
    let origin: DispatchOrigin?
    let parameters: [String: JSONValue]?
    let inputs: [String: JSONValue]?
    let output: JSONValue?
    let outputs: [String: JSONValue]?
    let errorType: String?
    let errorMessage: String?
    let durationMs: Int?
    let action: String?
    let exitCode: Int?
    let outputPreview: String?
    let outputLen: Int?
    let inputPreview: String?
    let inputLen: Int?
    let timestamp: Date
    let rootID: String?
    let nodeID: String?
    let parentNodeID: String?
    let parentRunID: String?
    let asyncDispatch: Bool
    let absorbed: Bool

    // MARK: - Initializer
    init(
        kind: WorkflowEventKind,
        workflowID: String,
        workflowName: String,
        stepID: String? = nil,
        origin: DispatchOrigin? = nil,
        parameters: [String: JSONValue]? = nil,
        inputs: [String: JSONValue]? = nil,
        output: JSONValue? = nil,
        outputs: [String: JSONValue]? = nil,
        errorType: String? = nil,
        errorMessage: String? = nil,
        durationMs: Int? = nil,
        action: String? = nil,
        exitCode: Int? = nil,
        outputPreview: String? = nil,
        outputLen: Int? = nil,
        inputPreview: String? = nil,
        inputLen: Int? = nil,
        timestamp: Date = Date(),
        rootID: String? = nil,
        nodeID: String? = nil,
        parentNodeID: String? = nil,
        parentRunID: String? = nil,
        asyncDispatch: Bool? = nil,
        absorbed: Bool = false
    ) {
        self.kind = kind
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.stepID = stepID
        self.origin = origin ?? LogContext.workflowContext?.origin
        self.parameters = parameters ?? LogContext.parameters
        self.inputs = inputs
        self.output = output
        self.outputs = outputs
        self.errorType = errorType
        self.errorMessage = errorMessage
        self.durationMs = durationMs
        self.action = action
        self.exitCode = exitCode
        self.outputPreview = outputPreview
        self.outputLen = outputLen
        self.inputPreview = inputPreview
        self.inputLen = inputLen
        self.timestamp = timestamp
        self.rootID = rootID ?? LogContext.rootID
        self.nodeID = nodeID ?? LogContext.nodeID
        self.parentNodeID = parentNodeID ?? LogContext.parentNodeID
        self.parentRunID = parentRunID ?? LogContext.parentRunID
        self.asyncDispatch = asyncDispatch ?? LogContext.asyncDispatch ?? false
        self.absorbed = absorbed
    }

    // MARK: - Public
    func toJSONObject() -> [String: Any] {
        var object: [String: Any] = [
            "event": kind.rawValue,
            "workflow_id": workflowID,
            "workflow_name": workflowName,
            "ts": Int(timestamp.timeIntervalSince1970)
        ]

        if let stepID { object["step"] = stepID }
        if let origin { object["origin"] = origin.asPayload }
        if let parameters { object["parameters"] = parameters.mapValues(toAny) }
        if let inputs { object["inputs"] = inputs.mapValues(toAny) }
        if let output { object["output"] = toAny(output) }
        if let outputs { object["outputs"] = outputs.mapValues(toAny) }
        if let errorType { object["error_type"] = errorType }
        if let errorMessage { object["error_message"] = errorMessage }
        if let durationMs { object["duration_ms"] = durationMs }
        if let action { object["action"] = action }
        if let exitCode { object["exit_code"] = exitCode }
        if let outputPreview { object["output_preview"] = outputPreview }
        if let outputLen { object["output_len"] = outputLen }
        if let inputPreview { object["input_preview"] = inputPreview }
        if let inputLen { object["input_len"] = inputLen }
        if let rootID { object["root_id"] = rootID }
        if let nodeID { object["node_id"] = nodeID }
        if let parentNodeID { object["parent_node_id"] = parentNodeID }
        if let parentRunID { object["parent_run_id"] = parentRunID }
        if asyncDispatch { object["async"] = true }
        if absorbed { object["absorbed"] = true }

        return object
    }

    // MARK: - Private
    private func toAny(_ value: JSONValue) -> Any {
        switch value {
        case .null:
            return NSNull()

        case .bool(let bool):
            return bool

        case .int(let integer):
            return integer

        case .double(let double):
            return double

        case .string(let string):
            return string

        case .array(let array):
            return array.map(toAny)

        case .object(let object):
            return object.mapValues(toAny)
        }
    }
}
