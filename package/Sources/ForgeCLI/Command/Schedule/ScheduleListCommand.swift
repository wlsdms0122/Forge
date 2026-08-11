//
//  ScheduleListCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

private func renderTrigger(_ trigger: [String: Any]?) -> String {
    guard let trigger else { return "?" }
    
    if let every = trigger["every"] as? String { return "every \(every)" }
    
    if let once = trigger["once"] as? String {
        let timezone = trigger["timezone"] as? String ?? "?"
        
        return "once \(once) \(timezone)"
    }
    
    if let at = trigger["at"] as? String {
        let timezone = trigger["timezone"] as? String ?? "?"
        
        if let days = trigger["days"] as? [String], !days.isEmpty {
            return "at \(at) [\(days.joined(separator: ","))] \(timezone)"
        }
        
        return "at \(at) daily \(timezone)"
    }
    
    return "?"
}

struct ScheduleListCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List registered schedules."
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "schedule list")
        let result = client.call("schedule.list")
        
        if json {
            printJSON(result)
            
            return
        }
        
        let schedules = (result["schedules"] as? [[String: Any]]) ?? []
        
        if schedules.isEmpty {
            print("(no schedules registered)")
            
            return
        }
        
        for schedule in schedules {
            let id = schedule["id"] as? String ?? "?"
            let workflow = schedule["workflow"] as? String ?? "?"
            let trigger = renderTrigger(schedule["trigger"] as? [String: Any])
            let enabled = (schedule["enabled"] as? Bool) ?? true
            let runtime = (schedule["runtime"] as? Bool) ?? false
            let origin = runtime ? "runtime" : "config"
            let status: String
            
            if (schedule["spent"] as? Bool) == true {
                status = "spent"
            } else if let next = schedule["next_fire_at"] as? String {
                status = "next \(next)"
            } else {
                status = "-"
            }
            
            print("\(id)\t\(workflow)\t\(trigger)\t\(enabled ? "enabled" : "disabled")\t\(origin)\t\(status)")
        }
    }
    
    // MARK: - Private
}
