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
    let errorType: String?
    let errorMessage: String?
    let durationMs: Int?
    let action: String?
    let exitCode: Int?
    let timestamp: Date
    let rootID: String?
    let nodeID: String?
    let parentNodeID: String?
    let parentRunID: String?
    let asyncDispatch: Bool

    // The event's fields as the stream and the log write them. A value the
    // event carries is written with its preview.
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

        if let inputs {
            let preview = ValuePreview(.object(inputs))

            object["inputs"] = .object(inputs)
            object["input_preview"] = .string(preview.text)
            object["input_len"] = .int(preview.length)
        }

        if let output {
            let preview = ValuePreview(output)

            object["output"] = output
            object["output_preview"] = .string(preview.text)
            object["output_len"] = .int(preview.length)
        }

        if let errorType { object["error_type"] = .string(errorType) }
        if let errorMessage { object["error_message"] = .string(errorMessage) }
        if let durationMs { object["duration_ms"] = .int(durationMs) }
        if let action { object["action"] = .string(action) }
        if let exitCode { object["exit_code"] = .int(exitCode) }
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
        errorType: String? = nil,
        errorMessage: String? = nil,
        durationMs: Int? = nil,
        action: String? = nil,
        exitCode: Int? = nil,
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
        self.errorType = errorType
        self.errorMessage = errorMessage
        self.durationMs = durationMs
        self.action = action
        self.exitCode = exitCode
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
