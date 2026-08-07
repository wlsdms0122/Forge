//
//  WorkflowHealthCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

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
        let socketPath = try resolveSocket(global)
        let token = resolveToken(global.token)
        
        switch callRPC(
            socketPath: socketPath,
            method: "workflow.health",
            params: [:],
            token: token
        ) {
        case .err(let type, let message):
            dieRPC("workflow health", type: type, message: message)
        
        case .ok(let dict):
            if json {
                printJSON(dict)
                
                return
            }
            
            let runs = dict["runs"] as? [String: Any] ?? [:]
            let slots = dict["slots"] as? [String: Any] ?? [:]
            let dispatch = dict["dispatch"] as? [String: Any] ?? [:]
            let active = runs["active"] as? Int ?? 0
            let cap = runs["cap"] as? Int ?? 0
            let refused = runs["refused_total"] as? Int ?? 0
            
            var runLine = "runs   \(active) active / cap \(cap)"
            
            if refused > 0 { runLine += " (\(refused) refused)" }
            
            if let oldest = (runs["oldest"] as? [[String: Any]])?.first,
                let age = oldest["age_ms"] as? Int, active > 0 {
                runLine += "   oldest \(age / 1000)s (\(oldest["workflow_id"] as? String ?? "?") \(oldest["workflow_name"] as? String ?? "?"))"
            }
            
            print(runLine)
            
            let waiters = slots["waiters"] as? [[String: Any]] ?? []
            var slotLine = "slots  \(slots["free"] as? Int ?? 0) free / \(slots["max"] as? Int ?? 0) total"
            
            if !waiters.isEmpty {
                let maxWait = waiters.compactMap { waiter in waiter["waited_ms"] as? Int }.max() ?? 0
                slotLine += ", \(waiters.count) waiting (max \(maxWait / 1000)s)"
            }
            
            print(slotLine)
            print("rate   \(dispatch["last_60s"] as? Int ?? 0) dispatches / 60s")
            
            for tree in runs["trees"] as? [[String: Any]] ?? [] {
                let names = (tree["names"] as? [String: Int] ?? [:])
                    .sorted { lhs, rhs in lhs.value > rhs.value }
                    .map { pair in "\(pair.key)×\(pair.value)" }
                    .joined(separator: " ")
                
                print("tree   \(tree["root_id"] as? String ?? "?") \(tree["runs"] as? Int ?? 0) runs (\(names))")
            }
            
            let flags = dict["flags"] as? [[String: Any]] ?? []
            
            if flags.isEmpty {
                print("flags  none")
            } else {
                for flag in flags {
                    let kind = flag["kind"] as? String ?? "?"
                    let rest = flag
                        .filter { entry in entry.key != "kind" }
                        .map { entry in "\(entry.key)=\(entry.value)" }
                        .sorted()
                        .joined(separator: " ")
                    
                    print("flag   \(kind) \(rest)")
                }
            }
        }
    }
    
    // MARK: - Private
}
