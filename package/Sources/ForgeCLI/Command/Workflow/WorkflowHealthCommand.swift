//
//  WorkflowHealthCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

struct WorkflowHealthCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "health",
        abstract: "One-shot health check: slots, waiter ages, run trees, spawn rate, advisory flags."
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "workflow health")
        let result = client.call("workflow.health")
        
        if json {
            printJSON(result)
            
            return
        }
        
        let runs = result["runs"]
        let slots = result["slots"]
        let dispatch = result["dispatch"]
        let active = runs?["active"]?.intValue ?? 0
        let cap = runs?["cap"]?.intValue ?? 0
        let refused = runs?["refused_total"]?.intValue ?? 0
        
        var runLine = "runs   \(active) active / cap \(cap)"
        
        if refused > 0 { runLine += " (\(refused) refused)" }
        
        if let oldest = runs?["oldest"]?.arrayValue?.first,
            let age = oldest["age_ms"]?.intValue, active > 0 {
            runLine += "   oldest \(age / 1000)s (\(oldest["workflow_id"]?.stringValue ?? "?") \(oldest["workflow_name"]?.stringValue ?? "?"))"
        }
        
        print(runLine)
        
        let waiters = slots?["waiters"]?.arrayValue ?? []
        var slotLine = "slots  \(slots?["free"]?.intValue ?? 0) free / \(slots?["max"]?.intValue ?? 0) total"
        
        if !waiters.isEmpty {
            let maxWait = waiters.compactMap { waiter in waiter["waited_ms"]?.intValue }.max() ?? 0
            slotLine += ", \(waiters.count) waiting (max \(maxWait / 1000)s)"
        }
        
        print(slotLine)
        print("rate   \(dispatch?["last_60s"]?.intValue ?? 0) dispatches / 60s")
        
        for tree in runs?["trees"]?.arrayValue ?? [] {
            let names = (tree["names"]?.objectValue ?? [:])
                .compactMapValues(\.intValue)
                .sorted { lhs, rhs in lhs.value > rhs.value }
                .map { pair in "\(pair.key)×\(pair.value)" }
                .joined(separator: " ")
            
            print("tree   \(tree["root_id"]?.stringValue ?? "?") \(tree["runs"]?.intValue ?? 0) runs (\(names))")
        }
        
        let flags = result["flags"]?.arrayValue ?? []
        
        if flags.isEmpty {
            print("flags  none")
        } else {
            for flag in flags {
                let kind = flag["kind"]?.stringValue ?? "?"
                let rest = (flag.objectValue ?? [:])
                    .filter { entry in entry.key != "kind" }
                    .map { entry in "\(entry.key)=\(entry.value.plainText)" }
                    .sorted()
                    .joined(separator: " ")
                
                print("flag   \(kind) \(rest)")
            }
        }
    }
    
    // MARK: - Private
}
