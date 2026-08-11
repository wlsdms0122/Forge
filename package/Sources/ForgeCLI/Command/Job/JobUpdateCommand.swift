//
//  JobUpdateCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct JobUpdateCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Edit a job ticket (comment / brief / ref / plan item / status).",
        discussion: """
            All fields optional; pass any mix. Comments are the handover the next
            session (or the synthesizer reading sibling tickets) starts from — write
            what was done, why, and where things stand. Every edit is stamped with
            the caller token's id.

            EXAMPLE:
                forge job update <id> --item 2 --item-status done \\
                    --note "JobStore build passed"
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Job id.")
    var id: String
    
    @Option(help: "Append a comment (free text).")
    var note: String?
    
    @Option(help: "Set/replace the job brief (goal·background·constraints).")
    var brief: String?
    
    @Option(help: "Append a reference pointer (brain id / sandbox path / url) consulted this session.")
    var ref: String?
    
    @Option(name: .customLong("ref-note"), help: "One-line note for --ref (why it's relevant).")
    var refNote: String?
    
    @Option(help: "Plan item id to update.")
    var item: Int?
    
    @Option(name: .customLong("item-desc"), help: "Plan item description (set when creating).")
    var itemDesc: String?
    
    @Option(name: .customLong("item-status"), help: "Plan item status (free string — vocabulary is the client's convention).")
    var itemStatus: String?
    
    @Option(help: "Overall job status (free string — vocabulary is the client's convention).")
    var status: String?
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "job update")
        
        var params: [String: Any] = ["id": id]
        
        if let note { params["note"] = note }
        if let brief { params["brief"] = brief }
        if let ref { params["ref"] = ref }
        if let refNote { params["ref_note"] = refNote }
        if let item { params["item"] = item }
        if let itemDesc { params["item_desc"] = itemDesc }
        if let itemStatus { params["item_status"] = itemStatus }
        if let status { params["status"] = status }
        
        printResult(client.call("job.update", params), json: json)
    }
    
    // MARK: - Private
}
