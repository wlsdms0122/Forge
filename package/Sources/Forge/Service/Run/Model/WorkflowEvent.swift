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
    let runID: String
    let workflowName: String
    let stepID: String?
    let origin: DispatchOrigin?
    let parameters: [String: JSONValue]?
    let inputs: [String: JSONValue]?
    let output: JSONValue?
    let outputs: JSONValue?
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

    // The event's fields as the stream and the log write them.
    var fields: [String: JSONValue] {
        var object: [String: JSONValue] = [
            "event": .string(kind.rawValue),
            "run_id": .string(runID),
            "workflow_name": .string(workflowName),
            "ts": .int(Int(timestamp.timeIntervalSince1970))
        ]

        if let stepID { object["step"] = .string(stepID) }
        if let origin { object["origin"] = origin.jsonValue }
        if let parameters { object["parameters"] = .object(parameters) }
        if let inputs { object["inputs"] = .object(inputs) }
        if let output { object["output"] = output }
        if let outputs { object["outputs"] = outputs }
        if let errorType { object["error_type"] = .string(errorType) }
        if let errorMessage { object["error_message"] = .string(errorMessage) }
        if let durationMs { object["duration_ms"] = .int(durationMs) }
        if let action { object["action"] = .string(action) }
        if let exitCode { object["exit_code"] = .int(exitCode) }
        if let outputPreview { object["output_preview"] = .string(outputPreview) }
        if let outputLen { object["output_len"] = .int(outputLen) }
        if let inputPreview { object["input_preview"] = .string(inputPreview) }
        if let inputLen { object["input_len"] = .int(inputLen) }
        if let rootID { object["root_id"] = .string(rootID) }
        if let nodeID { object["node_id"] = .string(nodeID) }
        if let parentNodeID { object["parent_node_id"] = .string(parentNodeID) }
        if let parentRunID { object["parent_run_id"] = .string(parentRunID) }
        if asyncDispatch { object["async"] = true }

        return object
    }

    // MARK: - Initializer
    init(
        kind: WorkflowEventKind,
        runID: String,
        workflowName: String,
        stepID: String? = nil,
        origin: DispatchOrigin? = nil,
        parameters: [String: JSONValue]? = nil,
        inputs: [String: JSONValue]? = nil,
        output: JSONValue? = nil,
        outputs: JSONValue? = nil,
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
        asyncDispatch: Bool? = nil
    ) {
        self.kind = kind
        self.runID = runID
        self.workflowName = workflowName
        self.stepID = stepID
        self.origin = origin ?? WorkflowExecutionState.context?.origin
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
    }

    // MARK: - Public
    // MARK: - Private
}
