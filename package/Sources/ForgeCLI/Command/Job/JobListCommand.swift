//
//  JobListCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

struct JobListCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List job tickets (optionally filtered by origin or status)."
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Option(name: .customLong("origin-key"), help: "Filter by an origin-map key (e.g. thread_ts).")
    var originKey: String?
    
    @Option(name: .customLong("origin-value"), help: "Value the origin key must equal.")
    var originValue: String?
    
    @Option(help: "Filter to a status (free string — whatever vocabulary the tickets use).")
    var status: String?
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "job list")
        
        var params: [String: JSONValue] = [:]
        
        if let originKey { params["origin_key"] = .string(originKey) }
        if let originValue { params["origin_value"] = .string(originValue) }
        if let status { params["status"] = .string(status) }
        
        let result = client.call("job.list", params)
        
        if json {
            printJSON(result)
            
            return
        }
        
        let jobs = result["jobs"]?.arrayValue ?? []
        
        if jobs.isEmpty {
            print("(no jobs)")
            
            return
        }
        
        for job in jobs {
            let id = job["id"]?.stringValue ?? "?"
            let status = job["status"]?.stringValue ?? "?"
            let title = job["title"]?.stringValue ?? ""
            let parent = job["parent_job"]?.stringValue
                .map { parentID in " ↳\(parentID)" } ?? ""
            let open = (job["open"]?.boolValue ?? false) ? " ●open" : ""
            let last = job["last_event"].map { event in
                " (\(event["kind"]?.stringValue ?? "?") @ \(event["ts"]?.stringValue ?? "?"))"
            } ?? ""
            
            print("\(id)\t[\(status)]\(open)\t\(title)\(parent)\(last)")
        }
    }
    
    // MARK: - Private
}
