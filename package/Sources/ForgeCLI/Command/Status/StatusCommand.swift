//
//  StatusCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
//

import ArgumentParser
import Foundation
import Forge

struct StatusCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the daemon's identity, effective config, and runtime counts."
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        // `daemon.status` is the daemon's token-free introspection method, so
        // status speaks with whatever the caller happened to pass.
        let client = Client(global, context: "status", token: global.token ?? "")
        
        switch client.send("daemon.status") {
        case .err(let type, let message):
            if type == "ClientError" {
                reportNotRunning(session: global.session, socketPath: client.socketPath)
            }
            
            client.fail(type: type, message: message)
        
        case .ok(let dictionary):
            if json {
                printJSON(dictionary)
                
                return
            }
            
            printPlain(dictionary)
        }
    }
    
    // MARK: - Private
    private func printPlain(_ dictionary: [String: Any]) {
        if let daemon = dictionary["daemon"] as? [String: Any] {
            for key in ["session", "version", "socket", "pid", "started_at", "uptime_s"] {
                if let value = daemon[key] { print("\(key):\(pad(key))\(value)") }
            }
        }
        
        if
            let config = dictionary["config"] as? [String: Any],
            let values = config["values"] as? [[String: Any]]
        {
            let toml = config["toml"] as? String ?? "(none)"
            
            print("\nconfig (toml: \(toml)):")
            
            let maxKey = values.compactMap { value in (value["key"] as? String)?.count }.max() ?? 0
            
            for value in values {
                let key = value["key"] as? String ?? "?"
                let text = value["value"] as? String ?? "?"
                let source = value["source"] as? String ?? "?"
                let gap = String(repeating: " ", count: maxKey - key.count)
                
                print("  \(key)\(gap)  = \(text)  ← \(source)")
            }
        }
        
        if let runtime = dictionary["runtime"] as? [String: Any] {
            print("\nruntime:")
            
            if let workflows = runtime["workflows"] { print("  workflows: \(workflows)") }
            
            if let schedules = runtime["schedules"] as? [String: Any] {
                print("  schedules: \(schedules["enabled"] ?? 0)/\(schedules["total"] ?? 0) enabled")
            }
            
            if let jobs = runtime["jobs"] { print("  jobs:      \(jobs)") }
            
            if let services = runtime["services"] as? [[String: Any]], !services.isEmpty {
                let parts = services.map { service in
                    "\(service["name"] ?? "?")=\(service["state"] ?? "?")"
                }
                
                print("  services:  \(parts.joined(separator: " "))")
            }
        }
    }
    
    private func pad(_ key: String) -> String {
        String(repeating: " ", count: max(1, 12 - key.count))
    }
    
    private func reportNotRunning(session: String?, socketPath: String) {
        if
            let home = try? Session.home(session: session),
            let data = try? Data(contentsOf: Session.runtimeInfo(in: home)),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            let message = "daemon not reachable at \(socketPath) but runtime.json exists "
                + "(pid \(object["pid"] ?? "?"), started \(object["started_at"] ?? "?")) — "
                + "likely crashed without clean shutdown\n"
            
            FileHandle.standardError.write(Data(message.utf8))
        } else {
            let message = "no daemon for this session — socket \(socketPath) not listening "
                + "(start one with `forge serve`)\n"
            
            FileHandle.standardError.write(Data(message.utf8))
        }
    }
}
