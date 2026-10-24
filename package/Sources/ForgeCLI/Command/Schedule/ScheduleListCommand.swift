//
//  ScheduleListCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation
import Forge

private func renderTrigger(_ trigger: JSONValue?) -> String {
    guard let trigger else { return "?" }
    
    if let every = trigger["every"]?.stringValue { return "every \(every)" }
    
    if let once = trigger["once"]?.stringValue {
        let timezone = trigger["timezone"]?.stringValue ?? "?"
        
        return "once \(once) \(timezone)"
    }
    
    if let at = trigger["at"]?.stringValue {
        let timezone = trigger["timezone"]?.stringValue ?? "?"
        
        if let days = trigger["days"]?.arrayValue?.compactMap(\.stringValue), !days.isEmpty {
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
        
        let schedules = result["schedules"]?.arrayValue ?? []
        
        if schedules.isEmpty {
            print("(no schedules registered)")
            
            return
        }
        
        for schedule in schedules {
            let id = schedule["id"]?.stringValue ?? "?"
            let workflow = schedule["workflow"]?.stringValue ?? "?"
            let trigger = renderTrigger(schedule["trigger"])
            let enabled = schedule["enabled"]?.boolValue ?? true
            let runtime = schedule["runtime"]?.boolValue ?? false
            let origin = runtime ? "runtime" : "config"
            let status: String
            
            if schedule["spent"]?.boolValue == true {
                status = "spent"
            } else if let next = schedule["next_fire_at"]?.stringValue {
                status = "next \(next)"
            } else {
                status = "-"
            }
            
            print("\(id)\t\(workflow)\t\(trigger)\t\(enabled ? "enabled" : "disabled")\t\(origin)\t\(status)")
        }
    }
    
    // MARK: - Private
}
