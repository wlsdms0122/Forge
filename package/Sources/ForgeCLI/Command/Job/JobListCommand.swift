//
//  JobListCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

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
        let socketPath = try resolveSocket(global)
        let token = resolveToken(global.token)
        
        var params: [String: Any] = [:]
        
        if let originKey { params["origin_key"] = originKey }
        if let originValue { params["origin_value"] = originValue }
        if let status { params["status"] = status }
        
        switch callRPC(
            socketPath: socketPath,
            method: "job.list",
            params: params,
            token: token
        ) {
        case .err(let type, let message):
            dieRPC("job list", type: type, message: message)
        
        case .ok(let dict):
            if json {
                printJSON(dict)
                
                return
            }
            
            let jobs = (dict["jobs"] as? [[String: Any]]) ?? []
            
            if jobs.isEmpty {
                print("(no jobs)")
                
                return
            }
            
            for job in jobs {
                let id = job["id"] as? String ?? "?"
                let status = job["status"] as? String ?? "?"
                let title = job["title"] as? String ?? ""
                let parent = (job["parent_job"] as? String)
                    .map { parentID in " ↳\(parentID)" } ?? ""
                let open = (job["open"] as? Bool ?? false) ? " ●open" : ""
                let last = (job["last_event"] as? [String: Any]).map { event in
                    " (\(event["kind"] as? String ?? "?") @ \(event["ts"] as? String ?? "?"))"
                } ?? ""
                
                print("\(id)\t[\(status)]\(open)\t\(title)\(parent)\(last)")
            }
        }
    }
    
    // MARK: - Private
}
