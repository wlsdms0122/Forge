//
//  JobCreateCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

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
    
    @Option(help: "Origin as an opaque JSON map (forge-agnostic; e.g. slack: {channel, thread_ts}).")
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
        
        var params: [String: Any] = ["title": title]
        
        if let brief { params["brief"] = brief }
        
        if let refs {
            guard let data = refs.data(using: .utf8),
                let array = try? JSONSerialization.jsonObject(with: data),
                array is [Any]
            else {
                die("job create: --refs must be a valid JSON array", code: 4)
            }
            
            params["refs"] = array
        }
        
        if let origin { params["origin"] = parseJSONObjectArg(origin, flag: "--origin") }
        
        if let plan {
            guard let data = plan.data(using: .utf8),
                let array = try? JSONSerialization.jsonObject(with: data),
                array is [Any]
            else {
                die("job create: --plan must be a valid JSON array", code: 4)
            }
            
            params["plan"] = array
        }
        
        if let parentJob { params["parent_job"] = parentJob }
        if let status { params["status"] = status }
        if let id { params["id"] = id }
        
        printResult(client.call("job.create", params), json: json)
    }
    
    // MARK: - Private
}
