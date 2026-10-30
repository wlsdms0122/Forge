//
//  JobCreateCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

struct JobCreateCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new job ticket.",
        discussion: """
            Returns the job id. Fill --brief so a stateless processor understands
            the task without re-reading the source thread, and --refs with
            knowledge pointers already consulted. Pass --origin to bind the ticket
            to its source context (e.g. a slack thread). A ticket can be created
            now and picked up later — creation and dispatch are separate acts.

            EXAMPLE:
                forge job create --title "refactor X" \\
                    --brief "Goal: ... . Background: ... . Constraints: ..." \\
                    --refs '[{"ref":"some-brain-note","note":"design"},{"ref":"sandbox/backend/x","note":"target repo"}]' \\
                    --origin '{"channel":"C..","thread_ts":".."}' \\
                    --plan '[{"desc":"step one"},{"desc":"step two"}]'
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Option(help: "Human-readable job title.")
    var title: String
    
    @Option(help: "Self-contained brief: goal, background, constraints. So a stateless processor understands the task without re-reading the source thread.")
    var brief: String?
    
    @Option(help: "Reference pointers JSON: [{\"ref\":\"brain-id|path|url\",\"note\":\"why\"}] or [\"ref\", ...]. Knowledge already consulted / worth consulting.")
    var refs: String?
    
    @Option(help: "Origin as an opaque JSON object (forge-agnostic; e.g. slack: {channel, thread_ts}).")
    var origin: String?
    
    @Option(help: "Plan JSON array: [{\"id\"?:int,\"desc\":\"...\",\"status\"?:\"...\"}] or [\"desc\", ...]. id is an integer — omit to auto-number from 1.")
    var plan: String?
    
    @Option(name: .customLong("parent-job"), help: "Parent job id (epic/sub-ticket hierarchy).")
    var parentJob: String?
    
    @Option(help: "Initial status (free string, default \"open\"; vocabulary is the client's convention).")
    var status: String?
    
    @Option(help: "Job id (default: auto-generated).")
    var id: String?
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "job create")
        
        var params: [String: JSONValue] = ["title": .string(title)]
        
        if let brief { params["brief"] = .string(brief) }
        
        if let refs { params["refs"] = JSONValue(arrayArgument: refs, flag: "--refs") }
        
        if let origin { params["origin"] = JSONValue(objectArgument: origin, flag: "--origin") }
        
        if let plan { params["plan"] = JSONValue(arrayArgument: plan, flag: "--plan") }
        
        if let parentJob { params["parent_job"] = .string(parentJob) }
        if let status { params["status"] = .string(status) }
        if let id { params["id"] = .string(id) }
        
        client.call("job.create", params).printResult(json: json)
    }
    
    // MARK: - Private
}
